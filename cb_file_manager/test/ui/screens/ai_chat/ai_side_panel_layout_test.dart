import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/models/ai/ai_message.dart';
import 'package:cb_file_manager/models/ai/ai_provider_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/ai_side_panel.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/chat_input_bar.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/model_selector_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _SeededBloc extends AiAgentBloc {
  _SeededBloc(AiAgentState initial)
    : super(providerService: AiProviderService()) {
    emit(initial);
  }
}

void main() {
  testWidgets('the model picker sits in the composer and new chat is one '
      'click from the header', (tester) async {
    final bloc = _SeededBloc(
      AiAgentState(
        conversationId: 'old',
        messages: [
          AiMessage(
            id: 'q',
            role: AiMessageRole.user,
            content: 'Earlier question',
            timestamp: DateTime(2026),
          ),
        ],
        providerModelCatalogs: const [
          AiProviderModelCatalog(
            providerId: 'p',
            providerName: 'Provider',
            apiType: AiApiType.openaiCompatible,
            authMode: AiProviderAuthMode.none,
            defaultModelName: 'model-a',
            models: ['model-a'],
          ),
        ],
        selectedProviderId: 'p',
        selectedModelName: 'model-a',
      ),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: AiSidePanel(
              bloc: bloc,
              onClose: () {},
              width: 380,
              onWidthChanged: (_) {},
              onWidthChangeEnd: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ChatInputBar),
        matching: find.byType(ModelSelectorButton),
      ),
      findsOneWidget,
    );
    expect(find.byType(ModelSelectorButton), findsOneWidget);
    expect(find.text('Earlier question'), findsOneWidget);

    // The picker sits at the bottom, so its menu opens upward and must end
    // right above it, however short the model list is.
    final picker = tester.getRect(find.byType(ModelSelectorButton));
    await tester.tap(find.byType(ModelSelectorButton));
    await tester.pumpAndSettle();
    final menu = tester.getRect(
      find
          .descendant(
            of: find.byType(Overlay).first,
            matching: find.byType(ListView),
          )
          .last,
    );
    expect(menu.bottom, lessThanOrEqualTo(picker.top));
    expect(picker.top - menu.bottom, lessThan(12));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-panel-new-conversation')));
    await tester.pumpAndSettle();
    expect(bloc.state.messages, isEmpty);
    expect(bloc.state.conversationId, isNot('old'));
  });
}
