import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/complaint_cubit.dart';

String? _validateRequired(String? value, String message) {
  if (value == null || value.trim().isEmpty) return message;
  return null;
}

String? _validateEmail(String? value, String message) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return message;
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return message;
  return null;
}

@RoutePage()
class ComplaintScreen extends StatefulWidget implements AutoRouteWrapper {
  const ComplaintScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ComplaintCubit(id: id),
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
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.submitComplaint),
        leading: const AutoLeadingButton(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(LinearPiActive.height),
          child: BlocSelector<ComplaintCubit, ComplaintState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(tt.screenHPadding),
            children: [
              // Type
              BlocSelector<ComplaintCubit, ComplaintState, (ComplaintType, bool)>(
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
                    decoration: InputDecoration(
                      labelText: l10n.labelComplaintType,
                      border: const OutlineInputBorder(),
                    ),
                  );
                },
              ),

              SizedBox(height: tt.sectionGap),

              // Details
              BlocSelector<ComplaintCubit, ComplaintState, bool>(
                selector: (state) => state.isLoading,
                builder: (_, isLoading) => TextFormField(
                  controller: _detailsController,
                  maxLines: 5,
                  autofocus: true,
                  enabled: !isLoading,
                  decoration: InputDecoration(
                    labelText: l10n.detailsRequired,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => _validateRequired(v, l10n.provideDetails),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => _validateEmail(v, l10n.emailValidationError),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                          if (_formKey.currentState?.validate() ?? false) {
                            await cubit.submit();
                          }
                        },
                  child: Text(l10n.buttonSubmitComplaint),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
