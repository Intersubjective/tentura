import 'package:validatorless/validatorless.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/complaint_cubit.dart';

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
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<ScreenCubit>()),
      BlocProvider(create: (_) => ComplaintCubit(id: id)),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ComplaintCubit, ComplaintState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _l10n = L10n.of(context)!;

  late final _cubit = context.read<ComplaintCubit>();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_l10n.submitComplaint),
      leading: const AutoLeadingButton(),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: kPaddingAll,
        children: [
          // Type
          BlocSelector<ComplaintCubit, ComplaintState, ComplaintType>(
            selector: (state) => state.type,
            builder: (_, type) => Theme(
              data: ThemeData.from(colorScheme: Theme.of(context).colorScheme),
              child: DropdownButtonFormField<ComplaintType>(
                initialValue: type,
                items: [
                  DropdownMenuItem(
                    value: ComplaintType.violatesCsaePolicy,
                    child: Text(_l10n.violatesCSAE),
                  ),
                  DropdownMenuItem(
                    value: ComplaintType.violatesPlatformRules,
                    child: Text(_l10n.violatesPlatformRules),
                  ),
                ],
                onChanged: _cubit.setType,
                decoration: InputDecoration(
                  labelText: _l10n.labelComplaintType,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),

          // Details
          Padding(
            padding: kPaddingV,
            child: TextFormField(
              maxLines: 5,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _l10n.detailsRequired,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: Validatorless.required(_l10n.provideDetails),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _cubit.setDetails,
            ),
          ),

          // Email
          Padding(
            padding: kPaddingV,
            child: TextFormField(
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: _l10n.feedbackEmail,
                border: const OutlineInputBorder(),
              ),
              validator: Validatorless.email(_l10n.emailValidationError),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _cubit.setEmail,
            ),
          ),

          // Submit
          Padding(
            padding: kPaddingV,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(padding: kPaddingV),
              onPressed: () async {
                if (_formKey.currentState?.validate() ?? false) {
                  await _cubit.submit();
                }
              },
              child: Text(_l10n.buttonSubmitComplaint),
            ),
          ),
        ],
      ),
    ),
  );
}
