import 'dart:typed_data';

/// Fills the masked pixels of an RGBA image from their surroundings.
///
/// Works from the edge of the hole inwards ("onion peel"): each ring takes a
/// distance-weighted average of the already known pixels around it, with the
/// original pixels counting more than filled ones. A few smoothing passes
/// over the hole then soften the seams between rings. Good for removing
/// small objects, blemishes and specks; large holes come out soft.
///
/// [mask] has one byte per pixel; non-zero marks a pixel to fill.
/// Returns a new buffer; the inputs are not modified. Pure Dart, so it can
/// run in an isolate.
Uint8List inpaintRgba(Uint8List rgba, Uint8List mask, int width, int height) {
  final pixelCount = width * height;
  assert(rgba.length == pixelCount * 4);
  assert(mask.length == pixelCount);

  final out = Uint8List.fromList(rgba);
  // 0 = hole, 1 = filled, 2 = original.
  final state = Uint8List(pixelCount);
  var holeCount = 0;
  for (var i = 0; i < pixelCount; i++) {
    if (mask[i] == 0) {
      state[i] = 2;
    } else {
      holeCount++;
    }
  }
  if (holeCount == 0 || holeCount == pixelCount) return out;

  final queued = Uint8List(pixelCount);
  var frontier = <int>[];
  for (var i = 0; i < pixelCount; i++) {
    if (state[i] == 0 && _hasKnownNeighbour(state, i, width, height)) {
      frontier.add(i);
      queued[i] = 1;
    }
  }

  const radius = 2;
  final fills = <int>[];
  while (frontier.isNotEmpty) {
    fills.clear();
    for (final index in frontier) {
      final x = index % width;
      final y = index ~/ width;
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0, total = 0.0;
      for (var dy = -radius; dy <= radius; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          final n = ny * width + nx;
          final known = state[n];
          if (known == 0) continue;
          final weight = (known == 2 ? 2.0 : 1.0) / (dx * dx + dy * dy);
          final p = n * 4;
          r += out[p] * weight;
          g += out[p + 1] * weight;
          b += out[p + 2] * weight;
          a += out[p + 3] * weight;
          total += weight;
        }
      }
      if (total == 0) continue;
      fills
        ..add(index)
        ..add((r / total).round())
        ..add((g / total).round())
        ..add((b / total).round())
        ..add((a / total).round());
    }

    // Commit the whole ring at once so it does not feed on itself.
    final next = <int>[];
    for (var k = 0; k < fills.length; k += 5) {
      final index = fills[k];
      final p = index * 4;
      out[p] = fills[k + 1];
      out[p + 1] = fills[k + 2];
      out[p + 2] = fills[k + 3];
      out[p + 3] = fills[k + 4];
      state[index] = 1;
    }
    for (var k = 0; k < fills.length; k += 5) {
      final index = fills[k];
      final x = index % width;
      final y = index ~/ width;
      void visit(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) return;
        final n = ny * width + nx;
        if (state[n] == 0 && queued[n] == 0) {
          queued[n] = 1;
          next.add(n);
        }
      }

      visit(x - 1, y);
      visit(x + 1, y);
      visit(x, y - 1);
      visit(x, y + 1);
    }
    // Pixels that found no known neighbour this time wait for the next ring.
    for (final index in frontier) {
      if (state[index] == 0) next.add(index);
    }
    if (next.length == frontier.length && fills.isEmpty) break;
    frontier = next;
  }

  _smoothHole(out, mask, width, height, passes: 4);
  return out;
}

bool _hasKnownNeighbour(Uint8List state, int index, int width, int height) {
  final x = index % width;
  final y = index ~/ width;
  return (x > 0 && state[index - 1] != 0) ||
      (x < width - 1 && state[index + 1] != 0) ||
      (y > 0 && state[index - width] != 0) ||
      (y < height - 1 && state[index + width] != 0);
}

void _smoothHole(
  Uint8List pixels,
  Uint8List mask,
  int width,
  int height, {
  required int passes,
}) {
  final holes = <int>[];
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] != 0) holes.add(i);
  }
  final values = Uint8List(holes.length * 4);
  for (var pass = 0; pass < passes; pass++) {
    for (var h = 0; h < holes.length; h++) {
      final index = holes[h];
      final x = index % width;
      final y = index ~/ width;
      var r = 0, g = 0, b = 0, a = 0, count = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          final p = (ny * width + nx) * 4;
          r += pixels[p];
          g += pixels[p + 1];
          b += pixels[p + 2];
          a += pixels[p + 3];
          count++;
        }
      }
      values[h * 4] = r ~/ count;
      values[h * 4 + 1] = g ~/ count;
      values[h * 4 + 2] = b ~/ count;
      values[h * 4 + 3] = a ~/ count;
    }
    for (var h = 0; h < holes.length; h++) {
      final p = holes[h] * 4;
      pixels[p] = values[h * 4];
      pixels[p + 1] = values[h * 4 + 1];
      pixels[p + 2] = values[h * 4 + 2];
      pixels[p + 3] = values[h * 4 + 3];
    }
  }
}
