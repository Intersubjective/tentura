abstract class EmailLinkPort {
  String absolute(String path);

  String manageUrl();

  String unsubscribeUrl({required String accountId, required String scope});
}
