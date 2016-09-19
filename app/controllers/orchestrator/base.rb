# frozen_string_literal: true

module Orchestrator
    class Base < ::ActionController::Base
        layout nil
        rescue_from Couchbase::Error::NotFound, with: :entry_not_found


        before_action :doorkeeper_authorize!, except: :options


        protected


        # This defines current_authority from coauth/lib/auth/authority
        include CurrentAuthorityHelper
        
    
        # Couchbase catch all
        def entry_not_found(err)
            logger.warn err.message
            logger.warn err.backtrace.join("\n") if err.respond_to?(:backtrace) && err.backtrace
            head :not_found  # 404
        end

        # Helper for extracting the id from the request
        def id
            return @id if @id
            params.require(:id)
            @id = params.permit(:id)[:id]
        end

        # Used to save and respond to all model requests
        def save_and_respond(model)
            yield if model.save && block_given?
            render json: model
        end

        # Checking if the user is an administrator
        def check_admin
            user = current_user
            head :forbidden unless user && user.sys_admin
        end

        # Checking if the user is support personnel
        def check_support
            user = current_user
            head :forbidden unless user && (user.support || user.sys_admin)
        end

        # current user using doorkeeper
        def current_user
            @current_user ||= User.find(doorkeeper_token.resource_owner_id) if doorkeeper_token
        end
    end
end
