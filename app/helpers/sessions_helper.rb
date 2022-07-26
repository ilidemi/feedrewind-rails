module SessionsHelper
  def SessionsHelper::login_path_with_redirect(request)
    "/login?" + {"redirect" => request.original_fullpath}.to_param
  end
end
