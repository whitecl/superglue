module Breezy
  module XHRHeaders
    def redirect_back(fallback_location:, **args)
      if referer = request.headers["X-XHR-Referer"]
        redirect_to referer, **args
      else
        super
      end
    end

    def _compute_redirect_to_location(request, options)
      url = begin
        if options == :back && request.headers["X-XHR-Referer"]
          super(request, request.headers["X-XHR-Referer"])
        else
          super
        end
      end

      if request.xhr? && request.headers["X-BREEZY-REQUEST"]
        self.status = 200
        response.headers["X-BREEZY-LOCATION"] = url
      end

      url
    end

    private
      def set_response_url
        response.headers['X-RESPONSE-URL'] = request.fullpath
      end
  end
end
