typedef PhantomImportContact = ({String name, String? email, String? phone});

sealed class PhantomImportOutcome {
  const PhantomImportOutcome(this.rowIndex);

  final int rowIndex;
}

final class PhantomImportCreated extends PhantomImportOutcome {
  const PhantomImportCreated(
    super.rowIndex,
    this.id, {
    required this.alreadyOnTentura,
  });

  final String id;
  final bool? alreadyOnTentura;
}

final class PhantomImportRefused extends PhantomImportOutcome {
  const PhantomImportRefused(super.rowIndex, this.message);

  final String message;
}
