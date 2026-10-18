defmodule RobinahsShop.Release do
  @app :robinahs_shop
  def setup do
    Application.load(@app)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(RobinahsShop.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
        RobinahsShop.Shop.seed_catalogue()
        RobinahsShop.StockList.ensure_reference!()

        case RobinahsShop.Accounts.bootstrap_owner(
               System.get_env("ADMIN_EMAIL", ""),
               System.get_env("ADMIN_PASSWORD", "")
             ) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            raise "Owner setup failed: #{RobinahsShop.Shop.error_message(changeset)}"
        end
      end)

    :ok
  end

  def reset_password(email) do
    Application.load(@app)
    password = System.fetch_env!("NEW_STAFF_PASSWORD")

    if String.length(password) < 16 or String.length(password) > 128,
      do: raise("Password must be 16–128 characters")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(RobinahsShop.Repo, fn repo ->
        import Ecto.Query

        user =
          repo.get_by!(RobinahsShop.Staff, email: email |> String.trim() |> String.downcase())

        repo.transaction(fn ->
          repo.update!(
            Ecto.Changeset.change(user,
              password_hash: RobinahsShop.Accounts.hash_password(password),
              active: true
            )
          )

          repo.delete_all(from s in RobinahsShop.StaffSession, where: s.staff_id == ^user.id)
        end)
      end)

    :ok
  end
end
