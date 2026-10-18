defmodule RobinahsShop.AccountsTest do
  use RobinahsShop.DataCase, async: false

  test "passwords are hashed and bootstrap never resets an existing owner" do
    owner = owner_fixture()
    refute owner.password_hash == "test-password-long-enough"
    assert {:ok, _} = Accounts.authenticate("OWNER@example.com", "test-password-long-enough")
    assert {:error, :invalid_credentials} = Accounts.authenticate("owner@example.com", "wrong")

    assert {:ok, existing} =
             Accounts.bootstrap_owner("another@example.com", "another-long-password")

    assert existing.id == owner.id
    assert Accounts.verify_password("test-password-long-enough", existing.password_hash)
  end

  test "sessions expire and sign-out revokes the token" do
    owner = owner_fixture()
    token = Accounts.create_session(owner)
    assert Accounts.user_for_token(token).id == owner.id
    Accounts.revoke_session(token)
    assert is_nil(Accounts.user_for_token(token))
    token = Accounts.create_session(owner)
    session = Repo.get_by!(RobinahsShop.StaffSession, token_hash: Accounts.token_hash(token))

    Repo.update!(
      Ecto.Changeset.change(session, inserted_at: DateTime.add(DateTime.utc_now(), -32_400))
    )

    assert is_nil(Accounts.user_for_token(token))
  end

  test "cashiers cannot create accounts or grant themselves owner access" do
    owner = owner_fixture()
    cashier = staff_fixture(owner, "cashier")
    assert {:error, :forbidden} = Accounts.create_staff(cashier, %{"role" => "manager"})
    assert {:error, :forbidden} = Accounts.create_staff(owner, %{"role" => "owner"})
  end
end
