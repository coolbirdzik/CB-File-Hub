import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/ui/widgets/tag_input_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

class _Hierarchy extends Fake implements TagHierarchyManager {
  @override
  List<String> getChildren(String parentTag) => ['Alice', 'Bob', 'Carol'];
}

void main() {
  test(
    'an exact child name stays available as an autocomplete suggestion',
    () async {
      final result = await computeTagSuggestions(
        'People:Bob',
        hierarchyManager: _Hierarchy(),
        isSelected: (_) => false,
      );
      expect(result, ['Bob']);
    },
  );

  test(
    'completed and assigned children are excluded while the current entry matches',
    () async {
      final result = await computeTagSuggestions(
        'People:Alice, Bob',
        hierarchyManager: _Hierarchy(),
        isSelected: (tag) => tag == 'Carol',
      );
      expect(result, ['Bob']);
      expect(
        resolvePickedSuggestion('People:Alice, Bo', 'Bob'),
        'People:Alice,Bob',
      );
    },
  );
}
