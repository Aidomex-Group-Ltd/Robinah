RobinahsShop.Shop.seed_catalogue()
RobinahsShop.StockList.ensure_reference!()
RobinahsShop.Shop.seed_expenses()

case {System.get_env("ADMIN_EMAIL"), System.get_env("ADMIN_PASSWORD")} do
  {email, password} when is_binary(email) and is_binary(password) ->
    case RobinahsShop.Accounts.bootstrap_owner(email, password) do
      {:ok, _} -> IO.puts("Owner account is available; existing passwords are unchanged.")
      {:error, changeset} -> raise RobinahsShop.Shop.error_message(changeset)
    end

  _ ->
    IO.puts(
      "Catalogue seeded. Set ADMIN_EMAIL and ADMIN_PASSWORD and rerun seeds to create the owner."
    )
end
