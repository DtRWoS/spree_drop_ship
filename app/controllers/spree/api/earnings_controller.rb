module Spree
  module Api
    class EarningsController < Spree::Api::BaseController

      def show
        authorize! :read, Spree::Shipment
        supplier = Spree::Supplier.find_by(:email => CGI::unescape(params[:email]).downcase)
        if supplier.present?
          @earnings = Spree::Earning.new(supplier)
          render :json => @earnings.fetch
        else
          not_found
        end
      end
      
    end
  end
end