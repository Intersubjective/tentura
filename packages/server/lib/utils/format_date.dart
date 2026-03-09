String formatDate(DateTime? dateTime) => dateTime == null
    ? ''
    : '${dateTime.year}-${_pad(dateTime.month)}-${_pad(dateTime.day)}';

String _pad(int number) => number.toString().padLeft(2, '0');
