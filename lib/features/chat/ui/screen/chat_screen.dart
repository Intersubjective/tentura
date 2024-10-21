import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as chat;
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/widget/deep_back_button.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

import '../bloc/chat_cubit.dart';

@RoutePage()
class ChatScreen extends StatelessWidget implements AutoRouteWrapper {
  const ChatScreen({
    @queryParam this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (context) {
          final myProfile = GetIt.I<ProfileCubit>().state.profile;
          return ChatCubit(
            me: types.User(
              id: myProfile.id,
              firstName: myProfile.title,
              imageUrl: myProfile.imageId,
            ),
            friend: types.User(id: id),
          );
        },
        child: this,
      );

  @override
  Widget build(BuildContext context) {
    final chatCubit = context.read<ChatCubit>();
    final chatTheme = switch (GetIt.I<SettingsCubit>().state.themeMode) {
      ThemeMode.dark => const chat.DarkChatTheme(),
      ThemeMode.light => const chat.DefaultChatTheme(),
      ThemeMode.system =>
        MediaQuery.of(context).platformBrightness == Brightness.light
            ? const chat.DefaultChatTheme()
            : const chat.DarkChatTheme(),
    };
    return Scaffold(
      // Header
      appBar: AppBar(
        title: const Text('Chat'),
        leading: const DeepBackButton(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<ChatCubit, ChatState, FetchStatus>(
            selector: (state) => state.status,
            builder: (context, status) => status.isLoading
                ? const LinearPiActive()
                : const SizedBox(height: 4),
          ),
        ),
      ),

      // Chat
      body: BlocConsumer<ChatCubit, ChatState>(
        listener: showSnackBarError,
        listenWhen: (p, c) => c.hasError,
        buildWhen: (p, c) => c.status.isSuccess,
        builder: (context, state) => chat.Chat(
          user: state.me,
          theme: chatTheme,
          showUserNames: true,
          messages: state.messages,
          onSendPressed: chatCubit.onSendPressed,
          onMessageVisibilityChanged: chatCubit.onMessageVisibilityChanged,
        ),
      ),
    );
  }
}
