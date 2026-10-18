defmodule RobinahsShopWeb.ErrorHTML do
  use RobinahsShopWeb, :html
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule RobinahsShopWeb.ErrorJSON do
  def render(template, _),
    do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end
