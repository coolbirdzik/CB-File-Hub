import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewModeSpectrum.step', () {
    test('walks full desktop spectrum from tree toward largest grid', () {
      const supported = {
        ViewMode.tree,
        ViewMode.columns,
        ViewMode.details,
        ViewMode.list,
        ViewMode.tiles,
      };

      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tree,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.columns, 4),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.columns,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.details, 4),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.details,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.list, 4),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.list,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.tiles, 4),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tiles,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.grid, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.grid,
          currentZoom: 5,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.grid, 4),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.grid,
          currentZoom: UserPreferences.minGridZoomLevel,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(
          ViewMode.grid,
          UserPreferences.minGridZoomLevel,
        ),
      );
    });

    test('walks back from smallest grid into list/details/columns/tree', () {
      const supported = {
        ViewMode.tree,
        ViewMode.columns,
        ViewMode.details,
        ViewMode.list,
        ViewMode.tiles,
      };

      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.grid,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.tiles, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tiles,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.list, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.list,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.details, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.details,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.columns, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.columns,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.tree, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tree,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.tree, 5),
      );
    });

    test('skips unsupported modes', () {
      const supported = {ViewMode.tree, ViewMode.list};

      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tree,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.list, 4),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.list,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.grid, 5),
      );
    });

    test('tiles mode steps to grid or list on ctrl+scroll delta', () {
      const supported = {
        ViewMode.tree,
        ViewMode.columns,
        ViewMode.details,
        ViewMode.list,
        ViewMode.tiles,
      };

      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tiles,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.grid, 5),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.tiles,
          currentZoom: 4,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.list, 4),
      );
    });

    test('legacy gridPreview is treated as grid in the spectrum', () {
      const supported = {
        ViewMode.tree,
        ViewMode.columns,
        ViewMode.details,
        ViewMode.list,
        ViewMode.tiles,
      };

      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.gridPreview,
          currentZoom: 4,
          supported: supported,
          delta: 1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.grid, 3),
      );
      expect(
        ViewModeSpectrum.step(
          currentMode: ViewMode.gridPreview,
          currentZoom: 5,
          supported: supported,
          delta: -1,
          maxZoom: 5,
        ),
        const ViewSpectrumResult(ViewMode.tiles, 5),
      );
    });
  });
}
