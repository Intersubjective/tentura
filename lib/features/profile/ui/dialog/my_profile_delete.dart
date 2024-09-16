import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../bloc/profile_cubit.dart';

class MyProfileDeleteDialog extends StatelessWidget {
  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => const MyProfileDeleteDialog(),
      );

  const MyProfileDeleteDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
        title: const Text(
          'Are you sure you want to delete your profile?',
        ),
        content: const Text(
          'All your beacons and personal data will be deleted completely.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final authCubit = GetIt.I<AuthCubit>();
                await GetIt.I<ProfileCubit>().delete();
                await authCubit.removeAccount(authCubit.state.currentAccountId);
              } catch (e) {
                if (context.mounted) {
                  showSnackBar(
                    context,
                    isError: true,
                    text: e.toString(),
                  );
                }
              }
              if (context.mounted) await context.maybePop();
            },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: context.maybePop,
            child: const Text('Cancel'),
          ),
        ],
      );
}
