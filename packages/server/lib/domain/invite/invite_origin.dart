enum InviteOrigin {
  newAccount('new_account'),
  existingAccount('existing_account');

  const InviteOrigin(this.key);

  final String key;
}
