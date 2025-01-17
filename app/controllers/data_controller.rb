class DataController < ApplicationController

require 'csv'

  def itos(int)
    str = int.to_s
    size = str.size - 3
    while (size>0)
      str.insert(size,',')
      size -= 3
    end
    str
  end

  def map_to_hist_categories( arr )
    histo = {-10=>0, 60=>0, 100=>0, 150=>0}

    arr.each do |pe|
      pe = pe.round

      if pe <= 0
        pe = -10
      end

      if pe >= 60
        if pe >= 100
          pe = 100
        else
          pe = 60
        end
      end

      if !histo[pe]
        histo[pe] = 0
      end
      histo[pe] += 1
    end

    histo = Hash[histo.sort]
  end

  def histohash_to_comulitive(histo)
    comul = Hash[histo]
    kk = histo.values
    total = kk.inject(0){ |total,x| total+x }
    run_sum = 0
    histo.each do |k,v|
      run_sum += histo[k]
      comul[k] = ((run_sum.to_f/total) ).round(2)
    end
    comul
  end

  def find_median_pe(comu)
    comu.each do |k,v|
      return k if v >= 0.5
    end
  end


  def sppe
    #read file

    # @divisor = 8718720000 # Latest divisor 8718.72from 3/31/2016 - retrieved may 2016

    #makret cap and earnings for entire stock list, in Billions
    @total_market_cap = 0
    @pub_market_cap = 0
    @index_market_cap = 0
    @total_earnings = 0
    @index = 0 #get from google?
    @comp_data = []
    #lines = lines.first(10) #test first

    @multiticker_list = []
    @failed_tickers = []

    output_file = File.open(Rails.root.join('log','sp_evaluation_out.txt'),"w")

    # search for latest list instead...

    CSV.foreach(Rails.root.join('sp500',get_latest_list)) do |row|
      ticker = row[0].strip
      ticker = "BRK.B" if ticker == "BRK-B"
      ticker = "BF.B" if ticker == "BF-B"

      # Acquired - no longer listed:
#      next if ticker.to_s == "PCP" # Acquired - no longer listed
#      next if ticker.to_s == "BRCM" # Acquired - no longer listed

      stock = Stock.get_from_ticker(ticker)

      if (stock.nil? && ticker)
        ticker = ticker.gsub("-","")
        stock = Stock.joins(:share_classes).where( share_classes: {ticker: ticker}).first
      end

      if stock.nil?
        output_file.puts"Could not get stock object for ticker#{ticker}"
        @failed_tickers << ticker
        next
      end

      sc = nil
      if stock.has_multiple_public_classes?
        sc = Stock.get_stock_class_by_ticker(ticker)
      end

      if params[:price] == "Y"
        sc.nil? ? stock.update_price : sc.update_price
      else
        if sc.nil?
          stock.update_price if stock.updated_at < 1.day.ago
        else
          sc.update_price if sc.updated_at < 1.day.ago
        end
      end

      # Stocks that do not have yet 4 quarters worth of datat
      # As of Sep 1 2017:
      # BHGE, BHF, DWDP, DXC, INFO,


      # Get more recent data if needed!
      if params[:update] == "Y"
        if ticker !="PRGO"
          stock.update_financials if !stock.earnings_up_to_date?
        end
      end

      price = sc.nil? ? stock.price : sc.price

      ep = stock.ttm_earnings_record

      #first filing for HPE is annual for 2015
      ep = stock.annual_eps_newest_first.first if stock.ticker == "HPE"

      if ep.nil?
        output_file.puts"Could not get latest earnings record for #{ticker}"
        @failed_tickers << ticker
        next
      end

      #new
      net_income = ep.net_income.to_i
      revenue = ep.revenue.to_i
      ttm_eps = stock.ttm_eps

      #make sure share_of_float does as you think
      if !sc.nil?
        # net_income = net_income * sc.share_of_float
        # ttm_eps = (net_income * sc.share_of_float)/ sc.nshares.to_i
      end

      num_shares = sc.nil? ? stock.shares_float : sc.nshares.to_i
      ticker = sc.ticker if !sc.nil?
      spd = Spdata.new(ticker,
                       price,
                       ttm_eps,
                       net_income,
                       revenue,
                       num_shares)

      @index_market_cap += sc.nil? ? stock.public_market_cap : sc.market_cap

      if !@multiticker_list.include?(stock.ticker)
        @pub_market_cap += stock.public_market_cap
        @total_market_cap += stock.market_cap
        @total_earnings += ep.net_income.to_i

        output_file.puts "Total cap: #{itos(@total_market_cap.to_i)}"
        output_file.puts "PuMar cap: #{itos(@pub_market_cap.to_i)} After adding #{stock.ticker} to total"
        output_file.puts "           #{itos (@total_market_cap - @pub_market_cap).to_i}"
        output_file.puts "==================================================="
      end

      @multiticker_list << stock.ticker if !sc.nil?

      @comp_data << spd
    end
    output_file.close

    #create DB entry to save calculations
    @index_price = SpEarning.get_index_price
    @inferred_divisor = (@index_market_cap.to_f / @index_price)
    @divisor_earnings = (@total_earnings.to_f / @inferred_divisor)
    @spe = SpEarning.new( calc_date: Date.today,
                          list_file: get_latest_list,
                          num_included: @comp_data.size,
                          excluded_list: ar_to_s(@failed_tickers),
                          total_market_cap: @total_market_cap.to_i.to_s,
                          public_market_cap: @pub_market_cap.to_i.to_s,
                          index_market_cap: @index_market_cap.to_i.to_s,
                          total_earnings: @total_earnings.to_i.to_s,
                          market_pe: (@total_market_cap / @total_earnings).to_f,
                          index_price: @index_price,
                          inferred_divisor: @inferred_divisor,
                          divisor_earnings: @divisor_earnings,
                          divisor_pe: (@index_price / @divisor_earnings),
                          notes: "created from data_controller#sppe")


    @pes = @comp_data.map{ |d| d.pe }

    @pes = map_to_hist_categories(@pes)
    @comulper = histohash_to_comulitive(@pes)

    @spe.losers = @pes[-10]
    @spe.median_pe = find_median_pe(@comulper)
    @spe.save if (params[:save] == "Y")

    case params[:sort]
    when "E"
      @comp_data.sort_by! { |s| -s.ttm_earnings }
    when "R"
      @comp_data.sort_by! { |s| -s.revenue }
    when "M"
      @comp_data.sort_by! { |s| -s.margin }
    when "PE"
      @comp_data.sort_by! { |s| s.market_pe }
    else
      @comp_data.sort_by! { |s| -s.market_cap }
    end
    @time = Time.now.ctime
  end

  def get_latest_list( date = "")
    file_regex = /^sp500_list_\d\d.*\.txt$/
    date_regex = /(\d\d\d\d-\d\d-\d\d)/
    sp_lists = Dir.entries("sp500/").select{ |f| f =~ file_regex }

    return "" if sp_lists.empty?

    latest = "1980-01-01"
    sp_lists.each do |fs|
      fs_date = fs[date_regex,1].to_date
      l_date = latest[date_regex,1].to_date
      latest = fs if  l_date < fs_date
    end

    return latest
  end

  def ar_to_s(arr)
    str = arr.shift.to_s
    arr.each do |ar|
      str += " , " + ar.to_s
    end
  end


end
