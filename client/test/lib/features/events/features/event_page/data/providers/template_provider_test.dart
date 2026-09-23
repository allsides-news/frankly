import 'package:client/features/events/features/event_page/data/providers/template_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template getter throws before the template is loaded', () {
    final provider = TemplateProvider(
      communityId: 'community-id',
      templateId: 'template-id',
    );

    expect(provider.templateOrNull, isNull);
    expect(
      () => provider.template,
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Template must be loaded before being accessed.'),
        ),
      ),
    );
  });
}
