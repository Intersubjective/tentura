typedef PhantomImportContact = ({String name, String? email, String? phone});

sealed class PhantomImportOutcome {
  const PhantomImportOutcome(this.rowIndex);

  final int rowIndex;
}

final class PhantomImportCreated extends PhantomImportOutcome {
  const PhantomImportCreated(super.rowIndex, this.id);

  final String id;
}

final class PhantomImportRefused extends PhantomImportOutcome {
  const PhantomImportRefused(super.rowIndex, this.message);

  final String message;
}
