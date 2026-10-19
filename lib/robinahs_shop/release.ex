defmodule RobinahsShop.Release do
  @app :robinahs_shop

  def setup do
    Application.load(@app)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(RobinahsShop.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
        RobinahsShop.Shop.seed_catalogue()
        RobinahsShop.StockList.ensure_reference!()
        bootstrap_owner()
      end)

    :ok
  end

  # The owner account is only ever created on a new database, and only after
  # ADMIN_EMAIL and ADMIN_PASSWORD have been verified against the same rules as
  # the staff changeset. An existing owner — and every other staff account — is
  # left untouched, and no secret value is written to the log.
  defp bootstrap_owner do
    if RobinahsShop.Accounts.owner_exists?() do
      :ok
    else
      email = (System.get_env("ADMIN_EMAIL") || "") |> String.trim()
      password = System.get_env("ADMIN_PASSWORD") || ""
      verify_owner_credentials!(email, password)

      case RobinahsShop.Accounts.bootstrap_owner(email, password) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          raise "Owner setup failed: #{RobinahsShop.Shop.error_message(changeset)}"
      end
    end
  end

  defp verify_owner_credentials!(email, password) do
    add_problem = fn problems, problem?, message ->
      if problem?, do: problems ++ [message], else: problems
    end

    problems =
      []
      |> add_problem.(
        email == "",
        "ADMIN_EMAIL is not set. Set it to the owner's sign-in address."
      )
      |> add_problem.(
        email != "" and not Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email),
        "ADMIN_EMAIL is not a valid email address."
      )
      |> add_problem.(
        password == "",
        "ADMIN_PASSWORD is not set. Generate one with: openssl rand -base64 24"
      )
      |> add_problem.(
        password != "" and String.starts_with?(password, "REPLACE_WITH"),
        "ADMIN_PASSWORD is still the placeholder from .env.example."
      )
      |> add_problem.(
        password != "" and String.length(password) < 16,
        "ADMIN_PASSWORD must be at least 16 characters (it is #{String.length(password)}). " <>
          "Generate one with: openssl rand -base64 24"
      )
      |> add_problem.(
        password != "" and String.length(password) > 128,
        "ADMIN_PASSWORD must be at most 128 characters (it is #{String.length(password)})."
      )

    if problems != [] do
      raise """
      Cannot create the owner account: this database has no owner yet, so
      ADMIN_EMAIL and ADMIN_PASSWORD must be valid before the bootstrap runs.
      Fix these settings in Render → service → Environment and redeploy:

      #{Enum.map_join(problems, "\n", &("  - " <> &1))}

      A database that already has an owner is never modified, so these values
      are only checked while the first owner is created.
      """
    end

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
