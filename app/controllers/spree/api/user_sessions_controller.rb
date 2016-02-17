module Spree
  module Api
    class UserSessionsController < Spree::Api::BaseController

      def create
        authorize! :create, :spree_user
        unless params[:user].present?
          params.require(:user).permit(:email, :password)
          return
        end
        email = params[:user][:email].downcase
        @user = Spree::User.find_by_email(email)
        if @user.nil?
          not_found
          return
        end
        if @user.present? && !@user.valid_password?(params[:user][:password])
          unauthorized
          return
        end
        @user = sign_in :spree_user, @user
        respond_with(@user, :status => 200, :default_template => :show)
      end

      def destroy
        sign_out @user
        # session = ActiveRecord::SessionStore::Session.find_by_session_id(params[:user][:session])
        # session.destroy
        respond_with('', :status => 204)
      end

    end
  end
end