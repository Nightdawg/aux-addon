module 'aux.tabs.auctions'

local T = require 'T'
local aux = require 'aux'
local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'

local tab = aux.tab 'Auctions'

auction_records = T.acquire()

function tab.OPEN()
    frame:Show()
    scan_auctions()
end

function tab.CLOSE()
    frame:Hide()
end

function update_listing()
    listing:SetDatabase(auction_records)
end

function scan_undercut(undercutIndex, auctionCount, auction_records)

    status_bar:update_status((undercutIndex + 1) / auctionCount, 0)
    status_bar:set_text(format('Scanning undercuts (Auction %d / %d)', (undercutIndex + 1), auctionCount))

    local auction_record = auction_records[undercutIndex]
    undercutIndex = undercutIndex + 1
    auction_record['undercut'] = false
    local item_key = auction_record.item_key

    --Create Query
    local query = scan_util.item_query(auction_record.item_id) -- Not sure about auction_record.item_id

    scan_id = scan.start{
        type = 'list',
        ignore_owner = true,
		queries = T.list(query),
		on_auction = function(auction_record_inner)
                if auction_record_inner.item_key == item_key then
                    if auction_record_inner.unit_buyout_price < auction_record.unit_buyout_price then
                        auction_record['undercut'] = true
                        scan.abort(scan_id)
                    end
                end
		end,
        on_abort = function()
            --Was Undercutted, Start Next Scan
            if undercutIndex > auctionCount - 1 then
                --Call Next Undercut Scan Recursively
                scan_undercut(undercutIndex, auctionCount, auction_records)
            else
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan complete')
                update_listing()
            end
        end,
		on_complete = function()
			--Not Undercutted, Start Next Scan
            if undercutIndex > auctionCount - 1 then
                --Call Next Scan Recursively
                scan_undercut(undercutIndex, auctionCount, auction_records)
            else
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan complete')
                update_listing()
            end
        end,
	}
end

function M.scan_auctions()

    status_bar:update_status(0, 0)
    status_bar:set_text('Scanning auctions...')

    T.wipe(auction_records)
    update_listing()
    scan.start{
        type = 'owner',
        queries = {{blizzard_query = T.acquire()}},
        on_page_loaded = function(page, total_pages)
            status_bar:update_status(page / total_pages, 0)
            status_bar:set_text(format('Scanning (Page %d / %d)', page, total_pages))
        end,
        on_auction = function(auction_record)
            tinsert(auction_records, auction_record)
        end,
        on_complete = function()
            -- Scan for Undercuts for Each Auction
            local undercutIndex = 0;
            local auctionCount = table.getn(auction_records)

            if auctionCount > 0 then
                scan_undercut(undercutIndex, auctionCount, auction_records)
            else
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan complete')
                update_listing()
            end
        end,
        on_abort = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('Scan aborted')
        end,
    }
end

do
    local scan_id = 0
    local IDLE, SEARCHING, FOUND = aux.enum(3)
    local state = IDLE
    local found_index

    function find_auction(record)
        if not listing:ContainsRecord(record) then return end

        scan.abort(scan_id)
        state = SEARCHING
        scan_id = scan_util.find(
            record,
            status_bar,
            function() state = IDLE end,
            function() state = IDLE; listing:RemoveAuctionRecord(record) end,
            function(index)
                state = FOUND
                found_index = index

                cancel_button:SetScript('OnClick', function()
                    if scan_util.test(record, index) and listing:ContainsRecord(record) then
                        aux.cancel_auction(index, function() listing:RemoveAuctionRecord(record) end)
                    end
                end)
                cancel_button:Enable()
            end
        )
    end

    function on_update()
        if state == IDLE or state == SEARCHING then
            cancel_button:Disable()
        end

        if state == SEARCHING then return end

        local selection = listing:GetSelection()
        if not selection then
            state = IDLE
        elseif selection and state == IDLE then
            find_auction(selection.record)
        elseif state == FOUND and not scan_util.test(selection.record, found_index) then
            cancel_button:Disable()
            if not aux.cancel_in_progress() then state = IDLE end
        end
    end
end