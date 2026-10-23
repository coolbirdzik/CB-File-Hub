# File and Folder Listing UI Patterns

**Purpose**: Standard patterns for implementing file/folder listing screens that provide clear loading feedback and avoid confusing users.

## Critical Rule

**Never show empty state messages while data is still loading.** Users will think there are no files when they're simply still loading.

## Three Required States

Every listing screen must implement:
1. **Loading**: Show skeleton UI while fetching data
2. **Empty**: Show "no items" message only after loading completes
3. **Content**: Display actual items

## Loading State Pattern

Initialize with `bool _isLoadingItems = true` and always set to `false` in both success AND error handlers.

**Order matters in build method:**
```
1. Check if loading → show skeleton
2. Check if empty → show empty message
3. Show actual content
```

## Skeleton Loading Benefits

- Provides visual feedback that loading is happening
- Reduces perceived loading time
- Maintains layout structure during load
- Better UX than spinners alone

**Grid skeleton**: 20 placeholder items matching grid layout
**List skeleton**: 10 placeholder items with proper platform styling

## View Mode Guidelines

**Grid View**: For visual content (images/videos/folders with thumbnails)
- Images: 0.75 aspect ratio (portrait)
- Videos: 16/12 aspect ratio (landscape)
- Folders: 1.0 aspect ratio (square)

**List View**: For detailed file information
- Thumbnail size: 60x60 pixels
- Desktop: Wrapped in Card with shadow
- Mobile: Flat design, no Card wrapper

## Empty States

Only show after `_isLoadingItems == false`. Include appropriate icon and localized message.

## Error Handling

Always handle errors and update loading state. Provide retry button with error message display.

## Performance Tips

All available Details columns support ascending and descending sorting. Basic
file-stat fields retain the native sorter; tags, image dimensions, duration,
folder child counts, permissions and Windows Shell properties use the shared
`FilePropertySorter`. Load only the requested property, with bounded concurrency,
then compare cached raw values. Dimensions, duration, dates, ratings and bitrates
must not sort their localized display strings. Unknown values stay last in both
directions, with folders first and deterministic name/path ties. A newer sort or
navigation invalidates an in-flight metadata request. The selected sort remains
part of the existing per-folder preference; new enum values append to preserve
previously saved indexes. Cloud-only files are not hydrated to obtain sort keys.

- Implement scroll throttling for large lists
- Use `cacheExtent: 500` for GridView/ListView
- Show placeholders during fast scrolling
- Non-scrollable physics for skeleton loading

## Platform Differences

**Mobile**: Flat design, touch targets 48x48dp minimum, custom action bar
**Desktop**: Cards with shadows, hover states, standard AppBar

## Implementation Checklist

- [ ] Add `bool _isLoadingItems = true` state variable
- [ ] Set `_isLoadingItems = false` in success AND error handlers
- [ ] Implement `_buildSkeletonLoading()` for both grid and list
- [ ] Check loading state BEFORE empty state
- [ ] Handle errors with retry capability
- [ ] Test with slow network/large datasets

## Common Mistakes

❌ Checking if list is empty before checking loading state
❌ Showing spinner without skeleton structure
❌ Forgetting error handler loading state reset

✅ Always check loading state first
✅ Show skeleton matching content layout
✅ Update loading state in all code paths

## Reference Implementations

- Video Gallery: `lib/ui/screens/media_gallery/video_gallery_screen.dart`
- Image Gallery: `lib/ui/screens/media_gallery/image_gallery_screen.dart`

## Reusable Picker Dialog

Use the common media picker for any "browse + pick" flow instead of creating new dialogs.

**Location**: `lib/ui/dialogs/media_picker_dialog.dart`

**Features**:
- Folder navigation with path bar + refresh
- Search, sort, and grid/list toggle
- Media filter chips (configurable)
- Optional root restriction to keep users inside a folder

**Example**:
```dart
final picked = await showMediaPickerDialog(
  context,
  MediaPickerConfig(
    title: l10n.chooseThumbnail,
    initialPath: folderPath,
    rootPath: folderPath,
    restrictToRoot: true,
    fileFilter: (path) => FileTypeUtils.isImageFile(path),
    filters: [
      MediaPickerFilterOption(
        id: 'all',
        label: l10n.all,
        matches: (_) => true,
      ),
      MediaPickerFilterOption(
        id: 'images',
        label: l10n.images,
        matches: FileTypeUtils.isImageFile,
      ),
    ],
  ),
);
```
