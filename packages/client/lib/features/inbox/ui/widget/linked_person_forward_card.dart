import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';

class LinkedPersonForwardCard extends StatefulWidget {
  const LinkedPersonForwardCard({
    required this.offer,
    required this.onAnswered,
    super.key,
  });

  final LinkedPersonForwardOffer offer;
  final Future<void> Function() onAnswered;

  @override
  State<LinkedPersonForwardCard> createState() =>
      _LinkedPersonForwardCardState();
}

class _LinkedPersonForwardCardState extends State<LinkedPersonForwardCard> {
  bool _answering = false;

  Future<void> _answer({required bool confirm}) async {
    if (_answering) return;
    final onAnswered = widget.onAnswered;
    setState(() => _answering = true);
    try {
      if (confirm) {
        await GetIt.I<ForwardCase>().forwardOfferedRequest(widget.offer);
      }
      await onAnswered();
    } on Exception catch (error, stackTrace) {
      if (mounted) {
        showSnackBar(
          context,
          text: L10n.of(context)!.errorGenericAction,
          isError: true,
          error: error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    return Padding(
      padding: tt.listRowPadding,
      child: TenturaTechCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.linkedPersonForwardQuestion(
                widget.offer.requestTitle,
                widget.offer.name,
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SizedBox(height: tt.rowGap),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: tt.rowGap,
              children: [
                TextButton(
                  onPressed: _answering ? null : () => _answer(confirm: false),
                  child: Text(l10n.buttonCancel),
                ),
                FilledButton(
                  onPressed: _answering ? null : () => _answer(confirm: true),
                  child: Text(l10n.buttonYes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
