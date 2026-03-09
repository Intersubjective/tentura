import 'package:flutter/widgets.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

class Globals extends StatelessWidget {
  const Globals({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ContextCubit(fetchFromCache: false),
      ),
    ],
    child: child,
  );
}
