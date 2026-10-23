import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/complaint_cubit.dart';
import '../../domain/util/complaint_details.dart';
import '../../domain/util/feedback_email.dart';

String? _validateEmail(String? value, String message) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return null;
  if (!isValidFeedbackEmail(email)) return message;
  return null;
}

@RoutePage()
class ComplaintScreen extends StatefulWidget implements AutoRouteWrapper {
  const ComplaintScreen({
    @PathParam('id') this.id = '',
    @QueryParam('fixedType') this.fixedType = '',
    super.key,
  });

  final String id;
  final String fixedType;

  static ComplaintType? _parseFixedType(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    for (final type in ComplaintType.values) {
      if (type.name == raw) {
        return type;
      }
    }
    return null;
  }

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ComplaintCubit(
      id: id,
      fixedType: _parseFixedType(fixedType),
    ),
    child: this,
  );
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _detailsController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final initial = context.read<ComplaintCubit>().state;
    _detailsController = TextEditingController(text: initial.details);
    _emailController = TextEditingController(text: initial.email);
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _syncFieldsFromState(ComplaintState state) {
    if (_detailsController.text != state.details) {
      _detailsController.text = state.details;
    }
    if (_emailController.text != state.email) {
      _emailController.text = state.email;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ComplaintCubit>();
    final submitButtonStyle = FilledButton.styleFrom(
      minimumSize: Size.fromHeight(tt.buttonHeight),
    );

    return BlocListener<ComplaintCubit, ComplaintState>(
      listenWhen: (prev, curr) =>
          prev.details != curr.details || prev.email != curr.email,
      listener: (_, state) => _syncFieldsFromState(state),
      child: BlocSelector<ComplaintCubit, ComplaintState, ComplaintType?>(
        selector: (state) => state.fixedType,
        builder: (context, fixedType) {
          final isAccountDeletionRequest =
              fixedType == ComplaintType.accountDeletionRequest;
          // An in-shell page: Home's rail stays beside the form on regular
          // and expanded windows (#611); compact keeps the full screen.
          return HomeRailFrame(
            selectedTab: isAccountDeletionRequest
                ? HomeTab.me
                : widget.id.startsWith('U')
                ? HomeTab.network
                : HomeTab.work,
            child: Scaffold(
              appBar: TenturaTopBar.of(
                context,
                title: Text(
                  isAccountDeletionRequest
                      ? l10n.submitAccountDeletionRequest
                      : l10n.submitComplaint,
                ),
                leading: const AutoLeadingButton(),
                progress: BlocSelector<ComplaintCubit, ComplaintState, bool>(
                  selector: (state) => state.isLoading,
                  builder: TenturaTopBar.loadingBar,
                ),
              ),
              body: SafeArea(
                child: TenturaContentColumn(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: EdgeInsets.all(tt.screenHPadding),
                      children: [
                        BlocSelector<
                          ComplaintCubit,
                          ComplaintState,
                          (String, String)
                        >(
                          selector: (state) => (state.title, state.author),
                          builder: (_, item) {
                            final (title, author) = item;
                            if (title.isEmpty && author.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: EdgeInsets.only(bottom: tt.sectionGap),
                              child: _ReportedItem(
                                title: title,
                                author: author,
                              ),
                            );
                          },
                        ),

                        if (fixedType == null)
                          BlocSelector<
                            ComplaintCubit,
                            ComplaintState,
                            (ComplaintType?, bool)
                          >(
                            selector: (state) => (state.type, state.isLoading),
                            builder: (_, state) {
                              final (type, isLoading) = state;
                              return DropdownButtonFormField<ComplaintType>(
                                initialValue: type,
                                items: [
                                  DropdownMenuItem(
                                    value: ComplaintType.violatesCsaePolicy,
                                    child: Text(l10n.violatesCSAE),
                                  ),
                                  DropdownMenuItem(
                                    value: ComplaintType.violatesPlatformRules,
                                    child: Text(l10n.violatesPlatformRules),
                                  ),
                                ],
                                onChanged: isLoading ? null : cubit.setType,
                                hint: Text(l10n.complaintTypeHint),
                                validator: (v) => v == null
                                    ? l10n.complaintTypeRequired
                                    : null,
                                decoration: InputDecoration(
                                  labelText: l10n.labelComplaintType,
                                  border: const OutlineInputBorder(),
                                ),
                              );
                            },
                          ),

                        if (fixedType == null) SizedBox(height: tt.sectionGap),

                        // Details
                        BlocSelector<ComplaintCubit, ComplaintState, bool>(
                          selector: (state) => state.isLoading,
                          builder: (_, isLoading) => TextFormField(
                            controller: _detailsController,
                            maxLines: 5,
                            autofocus: true,
                            enabled: !isLoading,
                            decoration: InputDecoration(
                              labelText: l10n.detailsRequired(
                                kComplaintDetailsMinLength,
                              ),
                              border: const OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                            validator: (v) => validateComplaintDetails(
                              v,
                              l10n.complaintDetailsTooShort(
                                kComplaintDetailsMinLength,
                              ),
                            ),
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            onChanged: cubit.setDetails,
                          ),
                        ),

                        SizedBox(height: tt.sectionGap),

                        // Email
                        BlocSelector<ComplaintCubit, ComplaintState, bool>(
                          selector: (state) => state.isLoading,
                          builder: (_, isLoading) => TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            enabled: !isLoading,
                            decoration: InputDecoration(
                              labelText: l10n.feedbackEmail,
                              helperText: fixedType == null
                                  ? l10n.complaintEmailUse
                                  : null,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _validateEmail(v, l10n.emailValidationError),
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            onChanged: cubit.setEmail,
                            onFieldSubmitted: (_) {
                              if (_formKey.currentState?.validate() ?? false) {
                                unawaited(cubit.submit());
                              }
                            },
                          ),
                        ),

                        SizedBox(height: tt.sectionGap),

                        // Submit
                        BlocSelector<ComplaintCubit, ComplaintState, bool>(
                          selector: (state) => state.isLoading,
                          builder: (_, isLoading) => FilledButton(
                            style: submitButtonStyle,
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (_formKey.currentState?.validate() ??
                                        false) {
                                      await cubit.submit();
                                    }
                                  },
                            child: Text(
                              isAccountDeletionRequest
                                  ? l10n.buttonSubmitAccountDeletionRequest
                                  : l10n.buttonSubmitComplaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The item being reported: its title, and its author when there is one.
class _ReportedItem extends StatelessWidget {
  const _ReportedItem({required this.title, required this.author});

  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            style: textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (author.isNotEmpty)
          Text(
            author,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
