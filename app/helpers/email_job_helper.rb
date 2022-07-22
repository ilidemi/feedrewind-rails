module EmailJobHelper
  def EmailJobHelper.get_client_and_metadata
    if Rails.env.development? || Rails.env.test?
      #noinspection RailsChecklist05
      test_metadata = TestSingleton.find("email_metadata")&.value
      if test_metadata
        api_token = Rails.application.credentials.postmark_api_sandbox_token
      else
        api_token = Rails.application.credentials.postmark_api_token
      end
    else
      test_metadata = nil
      api_token = Rails.application.credentials.postmark_api_token
    end
    raise "Postmark API token not found" unless api_token
    postmark_client = Postmark::ApiClient.new(api_token)

    [postmark_client, test_metadata]
  end
end
