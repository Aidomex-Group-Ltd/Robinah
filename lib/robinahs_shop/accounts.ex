defmodule RobinahsShop.Accounts do
  import Ecto.Query
  alias RobinahsShop.{Repo, Staff, StaffSession}

  @permissions %{
    sale: [:owner, :manager, :cashier],
    receive: [:owner, :manager, :receiver],
    manage: [:owner, :manager],
    report: [:owner, :manager],
    team: [:owner]
  }

  def allowed?(%Staff{id: id}, action) do
    case Repo.get(Staff, id) do
      %Staff{active: true, role: role} -> role in Map.get(@permissions, action, [])
      _ -> false
    end
  end

  def allowed?(_, _), do: false

  def create_staff(actor, attrs) do
    if allowed?(actor, :team) and attrs["role"] in ["manager", "cashier", "receiver"] do
      insert_staff(attrs)
    else
      {:error, :forbidden}
    end
  end

  @doc """
  True when an owner account already exists, i.e. the database is not new.
  Owner bootstrap only ever runs against a database without one.
  """
  def owner_exists? do
    Repo.exists?(from u in Staff, where: u.role == :owner)
  end

  def bootstrap_owner(email, password) do
    case Repo.one(from u in Staff, where: u.role == :owner, limit: 1) do
      nil ->
        insert_staff(%{
          "email" => email,
          "name" => "Shop owner",
          "password" => password,
          "role" => "owner"
        })

      owner ->
        {:ok, owner}
    end
  end

  defp insert_staff(attrs) do
    changeset = Staff.changeset(%Staff{}, attrs)

    if changeset.valid? do
      changeset
      |> Ecto.Changeset.put_change(
        :password_hash,
        hash_password(Ecto.Changeset.get_change(changeset, :password))
      )
      |> Repo.insert()
    else
      {:error, changeset}
    end
  end

  def list_staff(actor),
    do: if(allowed?(actor, :team), do: Repo.all(from u in Staff, order_by: u.name), else: [])

  def deactivate_staff(actor, id) do
    if allowed?(actor, :team) do
      case Repo.get(Staff, id) do
        %Staff{role: role} = target when role != :owner ->
          Repo.transaction(fn ->
            Repo.update!(Ecto.Changeset.change(target, active: false))
            Repo.delete_all(from s in StaffSession, where: s.staff_id == ^target.id)
          end)

        _ ->
          {:error, :forbidden}
      end
    else
      {:error, :forbidden}
    end
  end

  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    normalized = email |> String.trim() |> String.downcase() |> String.slice(0, 254)

    with :ok <- RobinahsShop.LoginLimiter.attempt(normalized),
         %Staff{active: true} = user <- Repo.get_by(Staff, email: normalized),
         true <- verify_password(password, user.password_hash) do
      RobinahsShop.LoginLimiter.clear(normalized)
      {:ok, user}
    else
      :locked ->
        {:error, :locked}

      nil ->
        dummy_verify(password)
        {:error, :invalid_credentials}

      _ ->
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def hash_password(password) do
    rounds = Application.get_env(:robinahs_shop, :password_iterations, 600_000)
    salt = :crypto.strong_rand_bytes(16)
    digest = :crypto.pbkdf2_hmac(:sha256, password, salt, rounds, 32)
    Enum.join(["pbkdf2-sha256", rounds, Base.encode64(salt), Base.encode64(digest)], "$")
  end

  def verify_password(password, encoded) when byte_size(password) <= 512 do
    with ["pbkdf2-sha256", rounds, salt, digest] <- String.split(encoded, "$"),
         {iterations, ""} <- Integer.parse(rounds),
         {:ok, salt} <- Base.decode64(salt),
         {:ok, digest} <- Base.decode64(digest) do
      Plug.Crypto.secure_compare(
        :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, 32),
        digest
      )
    else
      _ -> false
    end
  end

  def verify_password(_, _), do: false

  defp dummy_verify(password),
    do:
      :crypto.pbkdf2_hmac(
        :sha256,
        String.slice(password, 0, 512),
        <<0::128>>,
        Application.get_env(:robinahs_shop, :password_iterations, 600_000),
        32
      )

  def create_session(user) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    Repo.insert!(%StaffSession{staff_id: user.id, token_hash: token_hash(token)})
    token
  end

  def user_for_token(token) when is_binary(token) and byte_size(token) <= 100 do
    cutoff = DateTime.add(DateTime.utc_now(), -28_800)

    Repo.one(
      from s in StaffSession,
        join: u in Staff,
        on: s.staff_id == u.id,
        where:
          s.token_hash == ^token_hash(token) and s.inserted_at > ^cutoff and u.active == true,
        select: u
    )
  end

  def user_for_token(_), do: nil

  def revoke_session(token) when is_binary(token) do
    Repo.delete_all(from s in StaffSession, where: s.token_hash == ^token_hash(token))
    RobinahsShopWeb.Endpoint.broadcast("staff_sessions:#{token_hash(token)}", "disconnect", %{})
    :ok
  end

  def revoke_session(_), do: :ok

  @doc """
  Keyed digest of a session token. When `JWT_SECRET` is configured the stored
  hash is an HMAC, so the secret cannot be used to forge session tokens from
  database reads. Changing the secret ends existing sessions; staff sign in
  again and no password data is touched.
  """
  def token_hash(token) do
    digest =
      case Application.get_env(:robinahs_shop, :session_hmac_secret) do
        secret when is_binary(secret) and byte_size(secret) > 0 ->
          :crypto.mac(:hmac, :sha256, secret, token)

        _ ->
          :crypto.hash(:sha256, token)
      end

    Base.encode16(digest, case: :lower)
  end
end
