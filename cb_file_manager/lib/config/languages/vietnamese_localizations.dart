import 'app_localizations.dart';

class VietnameseLocalizations implements AppLocalizations {
  @override
  String get appTitle => 'CB File Hub';

  // Common actions
  @override
  String get ok => 'Đồng ý';
  @override
  String get cancel => 'Hủy bỏ';
  @override
  String get save => 'Lưu lại';
  @override
  String get delete => 'Xóa';
  @override
  String get edit => 'Chỉnh sửa';
  @override
  String get close => 'Đóng';
  @override
  String get exit => 'Thoát';
  @override
  String get search => 'Tìm kiếm';
  @override
  String get all => 'Tất cả';
  @override
  String get settings => 'Cài đặt';

  @override
  String get moreOptions => 'Tùy chọn khác';

  // File operations
  @override
  String get copy => 'Sao chép';
  @override
  String get cut => 'Cắt';
  @override
  String get move => 'Di chuyển';
  @override
  String get rename => 'Đổi tên';
  @override
  String get newFolder => 'Thư mục mới';
  @override
  String get properties => 'Thuộc tính';
  @override
  String get openWith => 'Mở bằng';
  @override
  String get chooseDefaultApp => 'Chọn ứng dụng mặc định';
  @override
  String get setCoolBirdAsDefaultForVideos =>
      'Đặt CB File Hub làm mặc định cho file video';
  @override
  String get setCoolBirdAsDefaultForVideosAndroidHint =>
      'Đang mở Cài đặt. Trong "Mở theo mặc định", bật CB File Hub cho file video.';
  @override
  String get openFolder => 'Mở thư mục';
  @override
  String get openFile => 'Mở tệp';
  @override
  String get viewImage => 'Xem hình';
  @override
  String get open => 'Mở';
  @override
  String get pasteHere => 'Dán vào đây';
  @override
  String get manageTags => 'Quản lý thẻ';
  @override
  String get moveToTrash => 'Chuyển vào thùng rác';

  @override
  String get errorAccessingDirectory => 'Lỗi khi truy cập thư mục';
  @override
  String errorAccessingDirectoryWithError(String error) =>
      'Lỗi khi truy cập thư mục: $error';
  @override
  String accessDeniedAdminMessage(String path) =>
      'Truy cập bị từ chối: Cần quyền quản trị viên để truy cập $path';
  @override
  String directoryDoesNotExist(String path) => 'Thư mục không tồn tại: $path';

  // Action bar tooltips
  @override
  String get searchTooltip => 'Tìm kiếm';

  @override
  String get sortByTooltip => 'Sắp xếp theo';

  @override
  String get refreshTooltip => 'Làm mới';

  @override
  String get moreOptionsTooltip => 'Thêm tùy chọn';

  @override
  String get adjustGridSizeTooltip => 'Điều chỉnh kích thước item';

  @override
  String get columnSettingsTooltip => 'Thiết lập hiển thị cột';

  @override
  String get viewModeTooltip => 'Chế độ xem';

  // Dialog titles
  @override
  String get adjustGridSizeTitle => 'Điều chỉnh kích thước item';

  @override
  String get columnVisibilityTitle => 'Tùy chỉnh hiển thị cột';

  // Button labels
  @override
  String get apply => 'ÁP DỤNG';

  // Sort options
  @override
  String get sortNameAsc => 'Tên (A → Z)';

  @override
  String get sortNameDesc => 'Tên (Z → A)';

  @override
  String get sortDateModifiedOldest => 'Ngày sửa (Cũ nhất trước)';

  @override
  String get sortDateModifiedNewest => 'Ngày sửa (Mới nhất trước)';

  @override
  String get sortDateCreatedOldest => 'Ngày tạo (Cũ nhất trước)';

  @override
  String get sortDateCreatedNewest => 'Ngày tạo (Mới nhất trước)';

  @override
  String get sortSizeSmallest => 'Kích thước (Nhỏ nhất trước)';

  @override
  String get sortSizeLargest => 'Kích thước (Lớn nhất trước)';

  @override
  String get sortTypeAsc => 'Loại tệp (A → Z)';

  @override
  String get sortTypeDesc => 'Loại tệp (Z → A)';

  @override
  String get sortExtensionAsc => 'Đuôi tệp (A → Z)';

  @override
  String get sortExtensionDesc => 'Đuôi tệp (Z → A)';

  @override
  String get sortAttributesAsc => 'Thuộc tính (A → Z)';

  @override
  String get sortAttributesDesc => 'Thuộc tính (Z → A)';

  // View modes
  @override
  String get viewModeList => 'Danh sách';

  @override
  String get viewModeGrid => 'Lưới';

  @override
  String get viewModeDetails => 'Chi tiết';

  @override
  String get viewModeGridPreview => 'Lưới + Xem trước';

  @override
  String get previewPaneTitle => 'Xem trước';

  @override
  String get previewSelectFile => 'Chọn tệp để xem trước';

  @override
  String get previewNotSupported => 'Chưa hỗ trợ xem trước loại tệp này';

  @override
  String get previewUnavailable => 'Không thể xem trước';

  @override
  String get showPreview => 'Hiện xem trước';

  @override
  String get hidePreview => 'Ẩn xem trước';

  // Column names
  @override
  String get columnSize => 'Kích thước';

  @override
  String get columnType => 'Loại';

  @override
  String get columnDateModified => 'Ngày sửa đổi';

  @override
  String get columnDateCreated => 'Ngày tạo';

  @override
  String get columnAttributes => 'Thuộc tính';

  // Column descriptions
  @override
  String get columnSizeDescription => 'Hiển thị kích thước của file';

  @override
  String get columnTypeDescription => 'Hiển thị loại tệp tin (PDF, Word, v.v.)';

  @override
  String get columnDateModifiedDescription =>
      'Hiển thị ngày giờ tệp được sửa đổi';

  @override
  String get columnDateCreatedDescription =>
      'Hiển thị ngày giờ tệp được tạo ra';

  @override
  String get columnAttributesDescription =>
      'Hiển thị thuộc tính tệp (quyền đọc/ghi)';

  // Column visibility dialog
  @override
  String get columnVisibilityInstructions =>
      'Chọn các cột bạn muốn hiển thị trong chế độ xem chi tiết. '
      'Cột "Tên" luôn được hiển thị và không thể tắt.';

  // Grid size dialog
  @override
  String gridSizeLabel(int count) => 'Mức kích thước item: $count';

  @override
  String get gridSizeInstructions =>
      'Di chuyển thanh trượt để điều chỉnh kích thước item';

  // More options menu
  @override
  String get selectMultipleFiles => 'Chọn nhiều file';

  @override
  String get viewImageGallery => 'Xem thư viện ảnh';

  @override
  String get viewVideoGallery => 'Xem thư viện video';

  // Navigation
  @override
  String get home => 'Trang chủ';
  @override
  String get back => 'Quay lại';
  @override
  String get forward => 'Tiến tới';
  @override
  String get refresh => 'Làm mới';
  @override
  String get parentFolder => 'Thư mục chứa';

  // File types
  @override
  String get image => 'Hình ảnh';
  @override
  String get video => 'Video';
  @override
  String get audio => 'Âm thanh';
  @override
  String get document => 'Tài liệu';
  @override
  String get folder => 'Thư mục';
  @override
  String get file => 'Tệp tin';

  // File type labels
  @override
  String get fileTypeGeneric => 'Tệp tin';
  @override
  String get fileTypeJpeg => 'Ảnh JPEG';
  @override
  String get fileTypePng => 'Ảnh PNG';
  @override
  String get fileTypeGif => 'Ảnh GIF';
  @override
  String get fileTypeBmp => 'Ảnh BMP';
  @override
  String get fileTypeTiff => 'Ảnh TIFF';
  @override
  String get fileTypeWebp => 'Ảnh WebP';
  @override
  String get fileTypeSvg => 'Ảnh SVG';
  @override
  String get fileTypeMp4 => 'Video MP4';
  @override
  String get fileTypeAvi => 'Video AVI';
  @override
  String get fileTypeMov => 'Video MOV';
  @override
  String get fileTypeWmv => 'Video WMV';
  @override
  String get fileTypeFlv => 'Video FLV';
  @override
  String get fileTypeMkv => 'Video MKV';
  @override
  String get fileTypeMp3 => 'Âm thanh MP3';
  @override
  String get fileTypeWav => 'Âm thanh WAV';
  @override
  String get fileTypeAac => 'Âm thanh AAC';
  @override
  String get fileTypeFlac => 'Âm thanh FLAC';
  @override
  String get fileTypeOgg => 'Âm thanh OGG';
  @override
  String get fileTypePdf => 'Tài liệu PDF';
  @override
  String get fileTypeWord => 'Tài liệu Word';
  @override
  String get fileTypeExcel => 'Bảng tính Excel';
  @override
  String get fileTypePowerPoint => 'Bài thuyết trình PowerPoint';
  @override
  String get fileTypeTxt => 'Tệp văn bản';
  @override
  String get fileTypeRtf => 'Tài liệu RTF';
  @override
  String get fileTypeZip => 'Tệp nén ZIP';
  @override
  String get fileTypeRar => 'Tệp nén RAR';
  @override
  String get fileType7z => 'Tệp nén 7Z';
  @override
  String fileTypeWithExtension(String extension) => 'Tệp $extension';

  // Settings
  @override
  String get language => 'Ngôn ngữ';
  @override
  String get theme => 'Giao diện';
  @override
  String get darkMode => 'Chế độ tối';
  @override
  String get lightMode => 'Chế độ sáng';
  @override
  String get systemMode => 'Theo hệ thống';
  @override
  String get selectLanguage => 'Chọn ngôn ngữ bạn muốn sử dụng';
  @override
  String get selectTheme => 'Chọn giao diện hiển thị cho ứng dụng';
  @override
  String get selectThumbnailPosition =>
      'Chọn vị trí trích xuất hình thu nhỏ video';
  @override
  String get systemThemeDescription => 'Theo cài đặt giao diện của hệ thống';
  @override
  String get lightThemeDescription => 'Giao diện sáng cho tất cả màn hình';
  @override
  String get darkThemeDescription => 'Giao diện tối cho tất cả màn hình';
  @override
  String get themeOnboardingTitle => 'Chọn giao diện';
  @override
  String get themeOnboardingDescription =>
      'Chọn giao diện mặc định trước khi vào ứng dụng.';
  @override
  String get themeOnboardingLightLabel => 'Sáng';
  @override
  String get themeOnboardingDarkLabel => 'Tối';
  @override
  String get themeOnboardingMoreThemesMessage =>
      'Bạn có thể chọn thêm nhiều giao diện khác trong Cài đặt.';
  @override
  String get themeOnboardingContinue => 'Tiếp tục';
  @override
  String get vietnameseLanguage => 'Tiếng Việt';
  @override
  String get englishLanguage => 'Tiếng Anh';

  // Messages
  @override
  String get fileDeleteConfirmation =>
      'Bạn có chắc chắn muốn xóa tệp tin này không?';
  @override
  String get folderDeleteConfirmation =>
      'Bạn có chắc chắn muốn xóa thư mục này và tất cả nội dung bên trong không?';
  @override
  String get fileDeleteSuccess => 'Đã xóa tệp tin thành công';
  @override
  String get folderDeleteSuccess => 'Đã xóa thư mục thành công';
  @override
  String get operationFailed => 'Thao tác không thành công';

  // Tags
  @override
  String get tags => 'Thẻ';
  @override
  String get addTag => 'Thêm thẻ';
  @override
  String get removeTag => 'Xóa thẻ';
  @override
  String get tagListRefreshing => 'Đang làm mới danh sách thẻ...';
  @override
  String get tagManagement => 'Quản lý thẻ đánh dấu';
  @override
  String deleteTagConfirmation(String tag) => 'Xóa thẻ "$tag"?';
  @override
  String get tagDeleteConfirmationText =>
      'Thao tác này sẽ xóa thẻ khỏi tất cả các tệp. Hành động này không thể hoàn tác.';
  @override
  String tagDeleted(String tag) => 'Thẻ "$tag" đã được xóa thành công';
  @override
  String errorDeletingTag(String error) => 'Lỗi khi xóa thẻ: $error';
  @override
  String chooseTagColor(String tag) => 'Chọn màu cho thẻ "$tag"';
  @override
  String tagColorUpdated(String tag) => 'Màu cho thẻ "$tag" đã được cập nhật';
  @override
  String get allTags => 'Tất cả thẻ';
  @override
  String get filesWithTag => 'Tệp có thẻ "%s"';
  @override
  String get tagsInDirectory => 'Thẻ trong "%s"';
  @override
  String get aboutTags => 'Về quản lý thẻ';
  @override
  String get aboutTagsTitle => 'Giới thiệu về quản lý thẻ:';
  @override
  String get aboutTagsDescription =>
      'Thẻ giúp bạn tổ chức tệp bằng cách thêm nhãn tùy chỉnh. '
      'Bạn có thể thêm hoặc xóa thẻ khỏi các tệp, và tìm tất cả các tệp có thẻ cụ thể.';
  @override
  String get aboutTagsScreenDescription =>
      '• Tất cả thẻ trong thư viện của bạn\n'
      '• Các tệp được gắn thẻ đã chọn\n'
      '• Tùy chọn để xóa thẻ';
  @override
  String get deleteTag => 'Xóa thẻ này khỏi tất cả tệp';
  @override
  String get deleteAlbum => 'Xóa Album';

  // Tag Management Screen
  @override
  String get tagManagementTitle => 'Quản lý Tags';
  @override
  String get debugTags => 'Debug Tags';
  @override
  String get searchTags => 'Tìm kiếm';
  @override
  String get searchTagsHint => 'Tìm kiếm thẻ...';
  @override
  String get createNewTag => 'Tạo thẻ mới';
  @override
  String get newTagTooltip => 'Tạo thẻ mới';
  @override
  String get errorLoadingTags => 'Lỗi khi tải thẻ: ';
  @override
  String get noTagsFoundMessage => 'Không tìm thấy thẻ nào';
  @override
  String get noTagsFoundDescription => 'Tạo thẻ mới để bắt đầu phân loại tệp';
  @override
  String get createNewTagButton => 'Tạo thẻ mới';
  @override
  String noMatchingTagsMessage(String searchTags) =>
      'Không có thẻ nào phù hợp với "$searchTags"';
  @override
  String get clearSearch => 'Xóa tìm kiếm';
  @override
  String get tagManagementHeader => 'Quản lý thẻ';
  @override
  String get tagsCreated => 'thẻ đã tạo';
  @override
  String get tagManagementDescription =>
      'Nhấn vào thẻ để xem tất cả tệp có gắn thẻ đó. Sử dụng các nút bên phải để thay đổi màu hoặc xóa thẻ.';
  @override
  String get sortTags => 'Sắp xếp thẻ';
  @override
  String get sortByAlphabet => 'Theo bảng chữ cái';
  @override
  String get sortByPopular => 'Theo phổ biến';
  @override
  String get listViewMode => 'Chế độ danh sách';
  @override
  String get gridViewMode => 'Chế độ lưới';
  @override
  String get previousPage => 'Trang trước';
  @override
  String get nextPage => 'Trang sau';
  @override
  String get page => 'Trang';
  @override
  String get firstPage => 'Trang đầu';
  @override
  String get lastPage => 'Trang cuối';
  @override
  String get clickToViewFiles => 'Nhấn để xem tệp';
  @override
  String get changeTagColor => 'Thay đổi màu sắc';
  @override
  String get deleteTagFromAllFiles => 'Xóa thẻ này khỏi tất cả tệp';
  @override
  String get openInNewTab => 'Mở trong tab mới';
  @override
  String get viewFilesWithTag => 'Xem tệp với thẻ';
  @override
  String get renameTag => 'Đổi tên thẻ';
  @override
  String tagRenamed(String oldTag, String newTag) =>
      'Thẻ "$oldTag" đã đổi tên thành "$newTag"';
  @override
  String get openInSplitView => 'Mở ở chế độ chia đôi';
  @override
  String get changeColor => 'Thay đổi màu';
  @override
  String get noFilesWithTag => 'Không tìm thấy tệp nào có thẻ này';
  @override
  String debugInfo(String tag) => 'Thông tin gỡ lỗi: đang tìm thẻ "$tag"';
  @override
  String get backToAllTags => 'Quay về tất cả thẻ';
  @override
  String get tryAgain => 'Thử lại';
  @override
  String get filesWithTagCount => 'tệp';
  @override
  String get viewDetails => 'Xem chi tiết';
  @override
  String get openContainingFolder => 'Mở thư mục chứa';
  @override
  String get editTags => 'Chỉnh sửa thẻ';
  @override
  String get newTagTitle => 'Tạo thẻ mới';
  @override
  String get enterTagName => 'Nhập tên thẻ...';
  @override
  String get tagName => 'Tên thẻ';
  @override
  String get enterNewTagName => 'Nhập tên thẻ mới...';
  @override
  String tagAlreadyExists(String tagName) => 'Thẻ "$tagName" đã tồn tại';
  @override
  String tagCreatedSuccessfully(String tagName) =>
      'Đã tạo thẻ "$tagName" thành công';
  @override
  String get errorCreatingTag => 'Lỗi khi tạo thẻ: ';
  @override
  String get tagsSavedSuccessfully => 'Đã lưu thay đổi thẻ thành công';
  @override
  String get selectTagToRemove => 'Vui lòng chọn thẻ để xóa:';
  @override
  String get doubleClickToRename => 'Nhấn đúp để đổi tên';
  @override
  String get openingFolder => 'Opening folder: ';
  @override
  String get folderNotFound => 'Thư mục không tìm thấy: ';
  @override
  String get refreshTags => 'Làm mới tags';
  @override
  String tagsRefreshed(int count) => 'Đã làm mới tags - $count tags đã tải';

  // Gallery
  @override
  String get imageGallery => 'Thư viện ảnh';
  @override
  String get videoGallery => 'Thư viện video';

  // Storage locations
  @override
  String get local => 'Cục bộ';
  @override
  String get networks => 'Mạng';

  // File operations related to networks
  @override
  String get download => 'Tải xuống';
  @override
  String get downloadFile => 'Tải tệp xuống';
  @override
  String get selectDownloadLocation => 'Chọn vị trí lưu tệp:';
  @override
  String get selectFolder => 'Chọn thư mục';
  @override
  String get browse => 'Duyệt...';
  @override
  String get upload => 'Tải lên';
  @override
  String get uploadFile => 'Tải tệp lên';
  @override
  String get selectFileToUpload => 'Chọn tệp để tải lên:';
  @override
  String get create => 'Tạo';
  @override
  String get folderName => 'Tên thư mục';

  // Additional translations for database settings
  @override
  String get databaseSettings => 'Cài đặt cơ sở dữ liệu';
  @override
  String get databaseStorage => 'Lưu trữ cơ sở dữ liệu';
  @override
  String get useDatabaseStorage => 'Sử dụng cơ sở dữ liệu SQLite';
  @override
  String get databaseDescription =>
      'Lưu trữ thẻ và tùy chọn trong cơ sở dữ liệu cục bộ';
  @override
  String get jsonStorage => 'Đang sử dụng tệp JSON cho lưu trữ cơ bản';
  @override
  String get databaseStorageEnabled =>
      'Đang sử dụng SQLite cho lưu trữ cơ sở dữ liệu hiệu quả';
  @override
  String get objectBoxStorage =>
      'Đang sử dụng SQLite cho lưu trữ cơ sở dữ liệu hiệu quả'; // Legacy

  // Cloud sync
  @override
  String get cloudSync => 'Đồng bộ hóa đám mây';
  @override
  String get enableCloudSync => 'Bật đồng bộ hóa đám mây';
  @override
  String get cloudSyncDescription => 'Đồng bộ hóa thẻ và tùy chọn lên đám mây';
  @override
  String get syncToCloud => 'Đồng bộ lên đám mây';
  @override
  String get syncFromCloud => 'Đồng bộ từ đám mây';
  @override
  String get cloudSyncEnabled => 'Thẻ và tùy chọn sẽ được đồng bộ lên đám mây';
  @override
  String get cloudSyncDisabled => 'Đồng bộ hóa đám mây đang tắt';
  @override
  String get enableDatabaseForCloud =>
      'Bật cơ sở dữ liệu SQLite để sử dụng đồng bộ đám mây';

  // Database statistics
  @override
  String get databaseStatistics => 'Thống kê cơ sở dữ liệu';
  @override
  String get totalUniqueTags => 'Tổng số thẻ duy nhất';
  @override
  String get taggedFiles => 'Tệp tin được gắn thẻ';
  @override
  String get popularTags => 'Thẻ phổ biến nhất';
  @override
  String get recentTags => 'Thẻ gần đây';
  @override
  String get selectedTags => 'Thẻ đã chọn:';
  @override
  String batchAddTags(int count) => 'Thêm thẻ cho $count tệp';
  @override
  String get applyingChanges => 'Đang áp dụng thay đổi...';
  @override
  String tagsUpdated(int count, int added, int removed) {
    var msg = 'Đã cập nhật tags cho $count tệp';
    final parts = <String>[];
    if (added > 0) parts.add('thêm $added');
    if (removed > 0) parts.add('xóa $removed');
    if (parts.isNotEmpty) msg += ' (${parts.join(', ')})';
    return msg;
  }
  @override
  String get tagSuggestions => 'Gợi ý thẻ';
  @override
  String get advancedDatabaseSettings => 'Cài đặt cơ sở dữ liệu nâng cao';
  @override
  String get noTagsFound => 'Không tìm thấy thẻ nào';
  @override
  String get refreshStatistics => 'Làm mới thống kê';

  // Raw Data Viewer
  @override
  String get viewRawData => 'Xem dữ liệu thô';
  @override
  String get rawDataPreferences => 'Cài đặt';
  @override
  String get rawDataTags => 'Thẻ file';
  @override
  String get rawDataDescription =>
      'Xem dữ liệu thô lưu trong database (để debug)';
  @override
  String get noDataFound => 'Không tìm thấy dữ liệu';

  // Import/Export
  @override
  String get importExportDatabase => 'Nhập/Xuất cơ sở dữ liệu';
  @override
  String get backupRestoreDescription =>
      'Sao lưu và khôi phục thẻ và mối quan hệ tệp tin';
  @override
  String get exportDatabase => 'Xuất cơ sở dữ liệu';
  @override
  String get exportSettings => 'Xuất cài đặt';
  @override
  String get importDatabase => 'Nhập cơ sở dữ liệu';
  @override
  String get importSettings => 'Nhập cài đặt';
  @override
  String get resetSettings => 'Đặt lại cài đặt';
  @override
  String get exportDescription => 'Lưu thẻ của bạn vào một tệp tin';
  @override
  String get importDescription => 'Khôi phục thẻ của bạn từ một tệp tin';
  @override
  String get completeBackup => 'Sao lưu toàn bộ';
  @override
  String get completeRestore => 'Khôi phục toàn bộ';
  @override
  String get exportAllData => 'Xuất tất cả cài đặt và dữ liệu cơ sở dữ liệu';
  @override
  String get importAllData => 'Nhập tất cả cài đặt và dữ liệu cơ sở dữ liệu';

  // Export/Import messages
  @override
  String get exportSuccess => 'Đã xuất thành công đến: ';
  @override
  String get exportFailed => 'Xuất không thành công';
  @override
  String get importSuccess => 'Đã nhập thành công';
  @override
  String get importFailed => 'Nhập không thành công hoặc đã hủy';
  @override
  String get importCancelled => 'Đã hủy nhập';
  @override
  String get errorExporting => 'Lỗi khi xuất: ';
  @override
  String get errorImporting => 'Lỗi khi nhập: ';

  // Video thumbnails
  @override
  String get videoThumbnails => 'Hình thu nhỏ video';
  @override
  String get thumbnailMode => 'Chế độ tạo';
  @override
  String get thumbnailModeFast => 'Nhanh';
  @override
  String get thumbnailModeCustom => 'Tùy chỉnh';
  @override
  String get thumbnailModeFastDescription =>
      'Dùng phương thức có sẵn của HĐH. Nhanh hơn nhưng vị trí cố định.';
  @override
  String get thumbnailModeCustomDescription =>
      'Dùng FFmpeg để trích xuất tại vị trí cụ thể. Chậm hơn nhưng kiểm soát tốt hơn.';
  @override
  String get thumbnailPosition => 'Vị trí hình thu nhỏ:';
  @override
  String get generatingAtPosition => 'Đang trích xuất tại';
  @override
  String get generatingFast => 'Chế độ nhanh';
  @override
  String get maxConcurrency => 'Số tác vụ song song';
  @override
  String get maxConcurrencyDescription =>
      'Giá trị cao tạo thumbnail nhanh hơn nhưng tốn nhiều CPU hơn';
  @override
  String get percentOfVideo => 'phần trăm của video';
  @override
  String get thumbnailDescription =>
      'Đặt vị trí trong video (tính bằng phần trăm tổng thời lượng) nơi hình thu nhỏ sẽ được trích xuất';
  @override
  String get useSystemDefaultForVideo =>
      'Dùng ứng dụng mặc định của hệ thống cho video';
  @override
  String get useSystemDefaultForVideoDescription =>
      'Bật: chạm video mở bằng app mặc định (vd. VLC). Tắt: dùng trình phát trong app.';
  @override
  String get useSystemDefaultForVideoEnabled =>
      'Video sẽ mở bằng ứng dụng mặc định của hệ thống';
  @override
  String get useSystemDefaultForVideoDisabled =>
      'Video sẽ mở bằng trình phát trong app';
  @override
  String get thumbnailCache => 'Bộ nhớ đệm hình thu nhỏ';
  @override
  String get thumbnailCacheDescription =>
      'Hình thu nhỏ video được lưu trong bộ nhớ đệm để cải thiện hiệu suất. Nếu hình thu nhỏ xuất hiện lỗi thời hoặc bạn muốn giải phóng dung lượng, bạn có thể xóa bộ nhớ đệm.';
  @override
  String get clearThumbnailCache => 'Xóa bộ nhớ đệm hình thu nhỏ';
  @override
  String get clearing => 'Đang xóa...';
  @override
  String get thumbnailCleared => 'Đã xóa tất cả hình thu nhỏ video';
  @override
  String get errorClearingThumbnail => 'Lỗi khi xóa hình thu nhỏ: ';

  // New tab
  @override
  String get newTab => 'Thẻ mới';

  // Admin access
  @override
  String get adminAccess => 'Yêu cầu quyền quản trị';
  @override
  String get adminAccessRequired =>
      'Ổ đĩa này yêu cầu quyền quản trị để truy cập';
  @override
  String get requiresAdminPrivileges => 'Yêu cầu quyền quản trị';
  @override
  String driveRequiresAdmin(String path) =>
      'Ổ đĩa $path yêu cầu quyền quản trị để truy cập.';
  @override
  String get trashBin => 'Thùng rác';

  // File system
  @override
  String get drives => 'Ổ đĩa';
  @override
  String get system => 'Hệ thống';

  // Settings data
  @override
  String get settingsData => 'Dữ liệu cài đặt';
  @override
  String get viewManageSettings => 'Xem và quản lý dữ liệu cài đặt';

  // About app
  @override
  String get aboutApp => 'Thông tin ứng dụng';
  @override
  String get appDescription => 'Trình quản lý tệp mạnh mẽ với khả năng gắn thẻ';
  @override
  String get version => 'Phiên bản: 1.0.0';
  @override
  String get developer => 'Phát triển bởi CB File Hub - ngtanhung41@gmail.com';

  // Empty state
  @override
  String get emptyFolder => 'Thư mục trống';
  @override
  String get noImagesFound => 'Không tìm thấy hình ảnh trong thư mục này';
  @override
  String get noVideosFound => 'Không tìm thấy video trong thư mục này';
  @override
  String get loading => 'Đang tải thông tin...';

  // File details
  @override
  String get fileSize => 'Kích thước';
  @override
  String get fileLocation => 'Vị trí';
  @override
  String get fileCreated => 'Tạo lúc';
  @override
  String get fileModified => 'Sửa lúc';
  @override
  String get fileName => 'Tên tệp';
  @override
  String get filePath => 'Đường dẫn';
  @override
  String get fileType => 'Loại tệp';
  @override
  String get fileLastModified => 'Lần cuối sửa';
  @override
  String get fileAccessed => 'Truy cập lúc';
  @override
  String get loadingVideo => 'Đang tải video...';
  @override
  String get errorLoadingImage => 'Lỗi khi tải hình ảnh';
  @override
  String errorLoadingImageWithError(String error) =>
      'Lỗi khi tải hình ảnh: $error';
  @override
  String get failedToDisplayImage => 'Không thể hiển thị hình ảnh';
  @override
  String get noImageDataAvailable => 'Không có dữ liệu hình ảnh';
  @override
  String get urlLoadingNotImplemented => 'Tải hình ảnh từ URL chưa được hỗ trợ';
  @override
  String get duration => 'Thời lượng';
  @override
  String get resolution => 'Độ phân giải';
  @override
  String get createCopy => 'Tạo bản sao';
  @override
  String get deleteFile => 'Xóa tệp';

  // Folder thumbnails
  @override
  String get folderThumbnail => 'Thumbnail thư mục';
  @override
  String get chooseThumbnail => 'Chọn thumbnail';
  @override
  String get clearThumbnail => 'Xóa thumbnail';
  @override
  String get thumbnailAuto => 'Tự động (video/ảnh đầu tiên)';
  @override
  String get folderThumbnailSet => 'Đã cập nhật thumbnail thư mục';
  @override
  String get folderThumbnailCleared => 'Đã xóa thumbnail thư mục';
  @override
  String get invalidThumbnailFile => 'Vui lòng chọn file ảnh hoặc video';
  @override
  String get noMediaFilesFound =>
      'Không tìm thấy ảnh hoặc video trong thư mục này';

  // Video actions
  @override
  String get share => 'Chia sẻ';
  @override
  String get playVideo => 'Phát video';
  @override
  String get videoInfo => 'Thông tin video';
  @override
  String get deleteVideo => 'Xóa video';
  @override
  String get loadingThumbnails => 'Đang tải thumbnail';
  @override
  String get deleteVideosConfirm => 'Xóa video?';
  @override
  String get deleteConfirmationMessage =>
      'Bạn có chắc chắn muốn xóa các video đã chọn? Hành động này không thể hoàn tác.';
  @override
  String videosSelected(int count) => '$count video đã chọn';
  @override
  String videosDeleted(int count) => 'Đã xóa $count video';
  @override
  String searchingFor(String query) => 'Tìm kiếm: "$query"';
  @override
  String get errorDisplayingVideoInfo => 'Không thể hiển thị thông tin video';
  @override
  String get searchVideos => 'Tìm kiếm video';
  @override
  String get enterVideoName => 'Nhập tên video...';

  // Selection and grid
  @override
  String? get selectMultiple => 'Chọn nhiều file';
  @override
  String? get gridSize => 'Kích thước lưới';

  @override
  String get searchOrEnterPath => 'Tìm kiếm hoặc nhập đường dẫn';

  @override
  String get pleaseCreateTabFirst => 'Vui lòng tạo một tab trước';

  @override
  String get viewMode => 'Chế độ xem';

  @override
  String get masonryLayout => 'Bố cục Masonry (Pinterest)';

  // File picker dialogs
  @override
  String get chooseBackupLocation => 'Chọn vị trí lưu bản sao lưu';
  @override
  String get chooseRestoreLocation => 'Chọn tệp sao lưu để khôi phục';
  @override
  String get saveSettingsExport => 'Lưu xuất cài đặt';
  @override
  String get saveDatabaseExport => 'Lưu xuất cơ sở dữ liệu';
  @override
  String get selectBackupFolder => 'Chọn thư mục sao lưu để nhập';

  // Sorting
  @override
  String get sort => 'Sắp xếp';
  @override
  String get sortByName => 'Sắp xếp theo tên';
  @override
  String get sortByPopularity => 'Sắp xếp theo độ phổ biến';
  @override
  String get sortByRecent => 'Sắp xếp theo gần đây';
  @override
  String get sortBySize => 'Sắp xếp theo kích thước';
  @override
  String get sortByDate => 'Sắp xếp theo ngày';

  // Bulk Selection
  @override
  String get bulkSelect => 'Chọn nhiều';
  @override
  String get selectAllTags => 'Chọn tất cả';
  @override
  String selectAllOnAllPages(int totalCount) => 'Chọn tất cả ($totalCount thẻ)';
  @override
  String get deselectAllTags => 'Bỏ chọn tất cả';
  @override
  String tagsSelected(int count) => 'Đã chọn $count thẻ';
  @override
  String bulkDeleteConfirmationTitle() => 'Xóa các thẻ đã chọn?';
  @override
  String bulkDeleteConfirmationText(int count) =>
      'Bạn có chắc muốn xóa $count thẻ? Hành động này không thể hoàn tác.';
  @override
  String bulkDeleteSuccess(int count) =>
      'Đã xóa thành công $count thẻ';

  // Search errors
  @override
  String noFilesFoundTag(Map<String, String> args) =>
      'Không tìm thấy tệp nào có tag "${args['tag']}"';

  @override
  String noFilesFoundTagGlobal(Map<String, String> args) =>
      'Không tìm thấy tệp nào có tag "${args['tag']}" trên toàn hệ thống';

  @override
  String noFilesFoundTags(Map<String, String> args) =>
      'Không tìm thấy tệp nào có các tag ${args['tags']}';

  @override
  String noFilesFoundTagsGlobal(Map<String, String> args) =>
      'Không tìm thấy tệp nào có các tag ${args['tags']} trên toàn hệ thống';

  @override
  String noFilesFoundQuery(Map<String, String> args) =>
      'Không tìm thấy kết quả cho "${args['query']}"';

  @override
  String errorSearchTag(Map<String, String> args) =>
      'Lỗi khi tìm kiếm theo tag: ${args['error']}';

  @override
  String errorSearchTagGlobal(Map<String, String> args) =>
      'Lỗi khi tìm kiếm theo tag trên toàn hệ thống: ${args['error']}';

  @override
  String errorSearchTags(Map<String, String> args) =>
      'Lỗi khi tìm kiếm với nhiều tag: ${args['error']}';

  @override
  String errorSearchTagsGlobal(Map<String, String> args) =>
      'Lỗi khi tìm kiếm với nhiều tag trên toàn hệ thống: ${args['error']}';

  // Search status
  @override
  String searchingTag(Map<String, String> args) =>
      'Đang tìm kiếm tag "${args['tag']}"...';

  @override
  String searchingTagGlobal(Map<String, String> args) =>
      'Đang tìm kiếm tag "${args['tag']}" trên toàn hệ thống...';

  @override
  String searchingTags(Map<String, String> args) =>
      'Đang tìm kiếm các tag ${args['tags']}...';

  @override
  String searchingTagsGlobal(Map<String, String> args) =>
      'Đang tìm kiếm các tag ${args['tags']} trên toàn hệ thống...';

  // Search UI
  @override
  String get searchTips => 'Mẹo tìm kiếm';

  @override
  String get searchTipsTitle => 'Mẹo tìm kiếm';

  @override
  String get viewTagSuggestions => 'Xem gợi ý tag';

  @override
  String get globalSearchModeEnabled => 'Đã chuyển sang tìm kiếm toàn cục';

  @override
  String get localSearchModeEnabled =>
      'Đã chuyển sang tìm kiếm thư mục hiện tại';

  @override
  String get globalSearchMode => 'Đang tìm kiếm toàn cục (nhấn để chuyển)';

  @override
  String get localSearchMode =>
      'Đang tìm kiếm thư mục hiện tại (nhấn để chuyển)';

  @override
  String get searchByFilename => 'Tìm theo tên tệp';

  @override
  String get searchByTags => 'Tìm theo tag';

  @override
  String get searchMultipleTags => 'Tìm nhiều tag';

  @override
  String get globalSearch => 'Tìm kiếm toàn cục';

  @override
  String get searchByNameOrTag => 'Tìm theo tên hoặc #tag';

  @override
  String get searchInSubfolders => 'Tìm trong thư mục con';

  @override
  String get featureNotImplemented => 'Tính năng sẽ được thêm sau';

  @override
  String get searchInAllFolders => 'Tìm trong tất cả thư mục';

  @override
  String get searchInCurrentFolder => 'Chỉ tìm trong thư mục hiện tại';

  @override
  String get searchShortcuts => 'Phím tắt';

  @override
  String get searchHintText => 'Tìm kiếm tệp hoặc dùng # để tìm theo tag';

  @override
  String get searchHintTextTags => 'Tìm theo tag... (ví dụ: #important #work)';

  @override
  String get suggestedTags => 'Tags gợi ý';

  @override
  String get noMatchingTags => 'Không tìm thấy tag phù hợp';

  @override
  String get results => 'kết quả';

  @override
  String searchResultsTitle(String countText) => 'Kết quả tìm kiếm$countText';

  @override
  String searchResultsTitleForQuery(String query, String countText) =>
      'Kết quả tìm kiếm cho "$query"$countText';

  @override
  String searchResultsTitleForTag(String tag, String countText) =>
      'Kết quả tìm kiếm cho tag "$tag"$countText';

  @override
  String searchResultsTitleForTagGlobal(String tag, String countText) =>
      'Kết quả tìm kiếm toàn cục cho tag "$tag"$countText';

  @override
  String searchResultsTitleForFilter(String filter, String countText) =>
      'Kết quả lọc cho "$filter"$countText';

  @override
  String searchResultsTitleForMedia(String mediaType, String countText) =>
      'Kết quả tìm kiếm cho $mediaType$countText';

  @override
  String get searchByFilenameDesc => 'Nhập tên tệp để tìm kiếm.';

  @override
  String get searchByTagsDesc =>
      'Sử dụng ký hiệu # để tìm theo tag. Ví dụ: #important';

  @override
  String get searchMultipleTagsDesc =>
      'Sử dụng nhiều tag cùng lúc để lọc kết quả chính xác hơn. Mỗi tag cần có ký tự # ở đầu và phải cách nhau bởi khoảng trắng. Ví dụ: #work #urgent #2023';

  @override
  String get globalSearchDesc =>
      'Bấm vào biểu tượng thư mục/toàn cầu để chuyển đổi giữa tìm kiếm thư mục hiện tại và toàn hệ thống.';

  @override
  String get searchShortcutsDesc =>
      'Nhấn Enter để bắt đầu tìm kiếm. Dùng phím mũi tên để chọn tag từ gợi ý.';

  // Permissions
  @override
  String get grantPermissionsToContinue => 'Cấp quyền để tiếp tục';

  @override
  String get permissionsDescription =>
      'Để sử dụng ứng dụng mượt mà, vui lòng cấp các quyền sau đây. Bạn có thể bỏ qua và cấp sau trong Cài đặt.';

  @override
  String get storagePermissionRequiredMessage =>
      'Cần cấp quyền truy cập tất cả files để xem đầy đủ nội dung thư mục. Vui lòng vào Settings > Apps > CB File Hub > Permissions và bật "All files access".';

  @override
  String get storagePhotosPermission => 'Quyền lưu trữ/ảnh';

  @override
  String get storagePhotosDescription =>
      'Ứng dụng cần quyền truy cập Ảnh/Tệp để hiển thị và phát nội dung cục bộ.';

  @override
  String get allFilesAccessPermission => 'Truy cập tất cả files (Quan trọng)';

  @override
  String get allFilesAccessDescription =>
      'Cần quyền này để hiển thị đầy đủ tất cả files bao gồm APK, documents và các file khác trong thư mục Download.';

  @override
  String get installPackagesPermission => 'Cài đặt gói (APK)';

  @override
  String get installPackagesDescription =>
      'Cần quyền này để mở và cài đặt các file APK thông qua Package Installer.';

  @override
  String get localNetworkPermission => 'Mạng cục bộ';

  @override
  String get localNetworkDescription =>
      'Cho phép truy cập mạng nội bộ để duyệt SMB/NAS trong cùng mạng.';

  @override
  String get notificationsPermission => 'Thông báo (tùy chọn)';

  @override
  String get notificationsDescription =>
      'Bật thông báo để nhận cập nhật phát và tác vụ nền.';

  @override
  String get grantAllPermissions => 'Cấp toàn bộ quyền';

  @override
  String get grantingPermissions => 'Đang cấp quyền...';

  @override
  String get enterApp => 'Vào app';

  @override
  String get skipEnterApp => 'Bỏ qua, vào app';

  @override
  String get granted => 'Đã cấp';

  @override
  String get grantPermission => 'Cấp quyền';

  // Home screen
  @override
  String get welcomeToFileManager => 'Chào mừng đến với CB File Hub';

  @override
  String get welcomeDescription => 'Trợ lý quản lý tệp mạnh mẽ của bạn';

  @override
  String get quickActions => 'Thao tác nhanh';

  @override
  String get browseFiles => 'Duyệt tệp';

  @override
  String get browseFilesDescription => 'Khám phá các tệp và thư mục cục bộ';

  @override
  String get manageMedia => 'Quản lý phương tiện';

  @override
  String get manageMediaDescription => 'Xem hình ảnh và video trong thư viện';

  @override
  String get tagFiles => 'Gắn thẻ tệp';

  @override
  String get tagFilesDescription => 'Tổ chức tệp bằng thẻ thông minh';

  @override
  String get networkAccess => 'Truy cập mạng';

  @override
  String get networkAccessDescription => 'Duyệt ổ đĩa và chia sẻ mạng';

  @override
  String get keyFeatures => 'Tính năng chính';

  @override
  String get fileManagement => 'Quản lý tệp';

  @override
  String get fileManagementDescription =>
      'Duyệt và tổ chức tệp một cách dễ dàng';

  @override
  String get smartTagging => 'Gắn thẻ thông minh';

  @override
  String get smartTaggingDescription =>
      'Gắn thẻ tệp để tìm kiếm nhanh như chớp';

  @override
  String get mediaGallery => 'Thư viện phương tiện';

  @override
  String get mediaGalleryDescription => 'Thư viện đẹp cho hình ảnh và video';

  @override
  String get networkSupport => 'Hỗ trợ mạng';

  @override
  String get networkSupportDescription => 'Truy cập liền mạch vào ổ đĩa mạng';

  // Settings screen
  @override
  String get interface => 'Giao diện';

  @override
  String get selectInterfaceTheme => 'Chọn giao diện và màu sắc yêu thích';

  @override
  String get chooseInterface => 'Chọn giao diện';

  @override
  String get interfaceDescription => 'Nhiều màu sắc và kiểu dáng khác nhau';

  @override
  String get showFileTags => 'Hiển thị tag của file';

  @override
  String get showFileTagsDescription =>
      'Hiển thị các tag của file bên ngoài danh sách file trong tất cả các chế độ xem';

  @override
  String get showFileTagsToggle => 'Hiển thị tag của file';

  @override
  String get showFileTagsToggleDescription =>
      'Bật/tắt hiển thị tag bên ngoài danh sách file';

  @override
  String get rememberTabWorkspace => 'Ghi nhớ không gian làm việc tab';

  @override
  String get rememberTabWorkspaceDescription =>
      'Khôi phục tab mở gần nhất và ghi nhớ trạng thái thu gọn của drawer theo từng tab.';

  @override
  String get cacheManagement => 'Quản lý bộ nhớ cache';

  @override
  String get cacheManagementDescription =>
      'Xóa dữ liệu cache để giải phóng bộ nhớ';

  @override
  String get cacheFolder => 'Thư mục cache:';

  @override
  String get networkThumbnails => 'Thumbnail mạng:';

  @override
  String get videoThumbnailsCache => 'Thumbnail video:';

  @override
  String get tempFiles => 'File tạm:';

  @override
  String get notInitialized => 'Chưa khởi tạo';

  @override
  String get refreshCacheInfo => 'Làm mới';

  @override
  String get cacheInfoUpdated => 'Đã cập nhật thông tin cache';

  @override
  String get clearVideoThumbnailsCache => 'Xóa cache video thumbnails';

  @override
  String get clearVideoThumbnailsDescription =>
      'Xóa các thumbnail video đã tạo';

  @override
  String get clearNetworkThumbnailsCache => 'Xóa cache SMB/network thumbnails';

  @override
  String get clearNetworkThumbnailsDescription =>
      'Xóa các thumbnail mạng đã tạo';

  @override
  String get clearTempFilesCache => 'Xóa các file tạm';

  @override
  String get clearTempFilesDescription => 'Xóa file tạm từ chia sẻ mạng';

  @override
  String get clearAllCache => 'Xóa tất cả cache';

  @override
  String get clearAllCacheDescription => 'Xóa tất cả dữ liệu cache';

  @override
  String get videoCacheCleared => 'Đã xóa cache thumbnails video';

  @override
  String get networkCacheCleared => 'Đã xóa cache thumbnails mạng';

  @override
  String get tempFilesCleared => 'Đã xóa các file tạm';

  @override
  String get allCacheCleared => 'Đã xóa tất cả dữ liệu cache';

  @override
  String get errorClearingCache => 'Lỗi: ';

  // Clipboard actions
  @override
  String copiedToClipboard(String name) => 'Đã sao chép "$name" vào clipboard';
  @override
  String cutToClipboard(String name) => 'Đã cắt "$name" vào clipboard';
  @override
  String get pasting => 'Đang dán...';

  // Rename dialogs
  @override
  String get renameFileTitle => 'Đổi tên tệp';
  @override
  String get renameFolderTitle => 'Đổi tên thư mục';
  @override
  String currentNameLabel(String name) => 'Tên hiện tại: $name';
  @override
  String get newNameLabel => 'Tên mới';
  @override
  String renamedFileTo(String newName) => 'Đã đổi tên tệp thành "$newName"';
  @override
  String renamedFolderTo(String newName) =>
      'Đã đổi tên thư mục thành "$newName"';

  // Downloads
  @override
  String downloadedTo(String location) => 'Đã tải xuống: $location';
  @override
  String downloadFailed(String error) => 'Tải xuống thất bại: $error';

  // Folder / Trash
  @override
  String get items => 'mục';

  @override
  String get files => 'tệp';

  @override
  String get deleteTitle => 'Xóa';

  @override
  String get permanentDeleteTitle => 'Xóa vĩnh viễn';

  @override
  String confirmDeletePermanent(String name) =>
      'Bạn có chắc chắn muốn xóa vĩnh viễn "$name"? Hành động này không thể hoàn tác.';

  @override
  String confirmDeletePermanentMultiple(int count) =>
      'Bạn có chắc chắn muốn xóa vĩnh viễn $count mục? Hành động này không thể hoàn tác.';

  @override
  String movedToTrash(String name) => '$name đã được chuyển vào thùng rác';
  @override
  String moveItemsToTrashConfirmation(int count, String itemType) =>
      'Chuyển $count $itemType vào thùng rác?';
  @override
  String get moveItemsToTrashDescription =>
      'Các mục này sẽ được chuyển vào thùng rác. Bạn có thể khôi phục chúng sau nếu cần.';
  @override
  String get clearFilter => 'Xóa bộ lọc';
  @override
  String filteredBy(String filter) => 'Lọc theo: $filter';
  @override
  String noFilesMatchFilter(String filter) =>
      'Không có tệp phù hợp với bộ lọc "$filter"';

  // Trash / Recycle Bin screen
  @override
  String get emptyTrash => 'Làm trống thùng rác';
  @override
  String get emptyTrashConfirm =>
      'Bạn có chắc chắn muốn xóa vĩnh viễn tất cả mục trong thùng rác? Hành động này không thể hoàn tác.';
  @override
  String get emptyTrashButton => 'LÀM TRỐNG THÙNG RÁC';
  @override
  String permanentlyDeleteItemsTitle(int count) => 'Xóa vĩnh viễn $count mục?';
  @override
  String get confirmPermanentlyDeleteThese =>
      'Hành động này không thể hoàn tác. Bạn có chắc chắn muốn xóa vĩnh viễn các mục này?';
  @override
  String itemRestoredSuccess(String name) => 'Đã khôi phục $name thành công';
  @override
  String failedToRestore(String name) => 'Không thể khôi phục $name';
  @override
  String errorRestoringItemWithError(String error) =>
      'Lỗi khi khôi phục mục: $error';
  @override
  String itemPermanentlyDeleted(String name) => 'Đã xóa vĩnh viễn $name';
  @override
  String failedToDelete(String name) => 'Không thể xóa $name';
  @override
  String failedToDeleteFilesCount(int count) => 'Không thể xóa $count tệp';
  @override
  String failedToDeleteItemsCount(int count) => 'Không thể xóa $count mục';
  @override
  String errorDeletingItemWithError(String error) => 'Lỗi khi xóa mục: $error';
  @override
  String get trashEmptiedSuccess => 'Đã làm trống thùng rác thành công';
  @override
  String get failedToEmptyTrash => 'Không thể làm trống thùng rác';
  @override
  String errorEmptyingTrashWithError(String error) =>
      'Lỗi khi làm trống thùng rác: $error';
  @override
  String itemsRestoredSuccess(int count) =>
      'Đã khôi phục thành công $count mục';
  @override
  String itemsRestoredWithFailures(int success, int failed) =>
      'Đã khôi phục $success mục, $failed thất bại';
  @override
  String itemsPermanentlyDeletedCount(int count) =>
      'Đã xóa vĩnh viễn $count mục';
  @override
  String itemsDeletedWithFailures(int success, int failed) =>
      'Đã xóa vĩnh viễn $success mục, $failed thất bại';
  @override
  String errorRestoringItemsWithError(String error) =>
      'Lỗi khi khôi phục các mục: $error';
  @override
  String errorDeletingItemsWithError(String error) =>
      'Lỗi khi xóa các mục: $error';
  @override
  String errorDeletingFilesWithError(String error) =>
      'Lỗi khi xóa các tệp: $error';
  @override
  String errorOpeningRecycleBinWithError(String error) =>
      'Lỗi khi mở Thùng rác: $error';
  @override
  String get restoreSelected => 'Khôi phục đã chọn';
  @override
  String get deleteSelected => 'Xóa đã chọn';
  @override
  String get selectItems => 'Chọn mục';
  @override
  String get openRecycleBin => 'Mở Thùng rác';
  @override
  String get emptyTrashTooltip => 'Làm trống thùng rác';
  @override
  String get trashIsEmpty => 'Thùng rác trống';
  @override
  String get itemsDeletedWillAppearHere => 'Các mục bạn xóa sẽ hiển thị ở đây';
  @override
  String originalLocation(String path) => 'Vị trí gốc: $path';
  @override
  String deletedAt(String date, String size) => 'Đã xóa: $date • $size';
  @override
  String get systemLabel => 'Hệ thống';
  @override
  String errorLoadingTrashItemsWithError(String error) =>
      'Lỗi khi tải mục trong thùng rác: $error';
  @override
  String get restoreTooltip => 'Khôi phục';
  @override
  String get deletePermanentlyTooltip => 'Xóa vĩnh viễn';

  // Misc helper labels
  @override
  String get networkFile => 'Tệp mạng';
  @override
  String tagCount(int count) => '$count thẻ';

  // Generic errors
  @override
  String errorGettingFolderProperties(String error) =>
      'Lỗi lấy thuộc tính thư mục: $error';
  @override
  String errorSavingTags(String error) => 'Lỗi khi lưu thẻ: $error';
  @override
  String errorCreatingFolder(String error) => 'Lỗi khi tạo thư mục: $error';
  @override
  String get pathNotAccessible =>
      'Đường dẫn không tồn tại hoặc không thể truy cập';

  // UI labels
  @override
  String get noStorageLocationsFound => 'Không tìm thấy vị trí lưu trữ nào';
  @override
  String get menuPinningOnlyLargeScreens =>
      'Ghim menu chỉ có trên màn hình lớn hơn';

  @override
  String get pinMenu => 'Ghim menu';

  @override
  String get unpinMenu => 'Bỏ ghim menu';

  @override
  String get pinnedSection => 'Đã ghim';

  @override
  String get pinToSidebar => 'Ghim vào thanh bên';

  @override
  String get unpinFromSidebar => 'Bỏ ghim khỏi thanh bên';

  @override
  String get pinnedToSidebar => 'Đã ghim vào thanh bên';

  @override
  String get removedFromSidebar => 'Đã bỏ ghim khỏi thanh bên';

  @override
  String get exitApplicationTitle => 'Thoát ứng dụng?';
  @override
  String moveToTrashConfirmMessage(String name) =>
      'Bạn có chắc chắn muốn chuyển "$name" vào thùng rác?';
  @override
  String get exitApplicationConfirm =>
      'Bạn có chắc chắn muốn thoát ứng dụng không?';
  @override
  String itemsSelected(int count) => '$count đã được chọn';
  @override
  String get noActiveTab => 'Không có tab hoạt động';
  @override
  String get masonryLayoutName => 'Bố cục Masonry (Pinterest)';
  @override
  String get undo => 'Hoàn tác';
  @override
  String errorWithMessage(String message) => 'Lỗi: $message';

  @override
  String get processing => 'Đang xử lý...';

  @override
  String get deletingFiles => 'Đang xóa tệp...';

  @override
  String get deletingItems => 'Đang xóa...';

  @override
  String get movingItemsToTrash => 'Đang chuyển vào thùng rác...';

  @override
  String get done => 'Xong';

  @override
  String get regenerateThumbnailsWithNewPosition =>
      'Tạo lại thumbnail với vị trí mới';

  @override
  String get thumbnailPositionUpdated =>
      'Đã xóa cache và sẽ tạo lại thumbnail với vị trí ';

  @override
  String get fileTagsEnabled => 'Đã bật hiển thị tag của file';

  @override
  String get fileTagsDisabled => 'Đã tắt hiển thị tag của file';

  // System screen router
  @override
  String get unknownSystemPath => 'Đường dẫn hệ thống không xác định';

  @override
  String get ftpConnectionRequired => 'Cần kết nối FTP';

  @override
  String get ftpConnectionDescription =>
      'Bạn cần kết nối đến máy chủ FTP trước.';

  @override
  String get goToFtpConnections => 'Đi đến kết nối FTP';

  @override
  String get cannotOpenNetworkPath => 'Không thể mở đường dẫn mạng';

  @override
  String get goBack => 'Quay lại';

  @override
  String get tagPrefix => 'Tag';

  // Network browsing
  @override
  String get ftpConnections => 'Kết nối FTP';

  @override
  String get smbNetwork => 'Mạng SMB';

  @override
  String get refreshData => 'Làm mới';

  @override
  String get addConnection => 'Thêm kết nối';

  @override
  String get noFtpConnections => 'Không có kết nối FTP nào.';

  @override
  String get activeConnections => 'Kết nối đang hoạt động';

  @override
  String get savedConnections => 'Kết nối đã lưu';

  @override
  String get connecting => 'Đang kết nối';

  @override
  String get connect => 'Kết nối';

  @override
  String get unknown => 'Không xác định';

  @override
  String get connectionError => 'Lỗi kết nối';

  @override
  String get loadCredentialsError => 'Lỗi khi tải thông tin đăng nhập đã lưu';

  @override
  String get networkScanFailed => 'Quét mạng thất bại';

  @override
  String get smbVersionUnknown => 'Không xác định';

  @override
  String get connectionInfoUnavailable => 'Thông tin kết nối không khả dụng';

  @override
  String get networkSettingsOpened => 'Đã mở cài đặt mạng';

  @override
  String get cannotOpenNetworkSettings =>
      'Không thể mở cài đặt mạng, vui lòng mở thủ công';

  @override
  String get networkDiscoveryDisabled => 'Khám phá mạng có thể chưa được bật';

  @override
  String get networkDiscoveryDescription =>
      'Bật khám phá mạng trong cài đặt Windows để quét máy chủ SMB';

  @override
  String get openSettings => 'Mở cài đặt';

  @override
  String get activeConnectionsTitle => 'Kết nối đang hoạt động';

  @override
  String get activeConnectionsDescription => 'Máy chủ SMB bạn đang kết nối';

  @override
  String get discoveredSmbServers => 'Máy chủ SMB đã khám phá';

  @override
  String get discoveredSmbServersDescription =>
      'Máy chủ được khám phá trên mạng cục bộ';

  @override
  String get noActiveSmbConnections => 'Không có kết nối SMB đang hoạt động';

  @override
  String get connectToSmbServer => 'Kết nối đến máy chủ SMB để xem tại đây';

  @override
  String get connected => 'Đã kết nối';

  @override
  String get openConnection => 'Mở kết nối';

  @override
  String get disconnect => 'Ngắt kết nối';

  @override
  String get scanningForSmbServers => 'Đang quét máy chủ SMB...';

  @override
  String get devicesWillAppear =>
      'Thiết bị sẽ xuất hiện ở đây khi được khám phá';

  @override
  String get scanningMayTakeTime => 'Quá trình này có thể mất vài phút';

  @override
  String get noSmbServersFound => 'Không tìm thấy máy chủ SMB nào';

  @override
  String get tryScanningAgain => 'Thử quét lại hoặc kiểm tra cài đặt mạng';

  @override
  String get scanAgain => 'Quét lại';

  @override
  String get readyToScan => 'Sẵn sàng quét';

  @override
  String get clickRefreshToScan =>
      'Nhấp nút làm mới để bắt đầu quét máy chủ SMB';

  @override
  String get startScan => 'Bắt đầu quét';

  @override
  String get foundDevices => 'Tìm thấy';

  @override
  String get scanning => 'Đang quét...';

  @override
  String get scanComplete => 'Quét hoàn tất';

  @override
  String get smbVersion => 'Phiên bản SMB';

  @override
  String get netbios => 'NetBIOS';

  // Network - additional
  @override
  String get selectAll => 'Chọn tất cả';
  @override
  String get unknownError => 'Đã xảy ra lỗi không xác định.';
  @override
  String get networkConnections => 'Kết nối mạng';
  @override
  String get availableServices => 'Dịch vụ có sẵn';
  @override
  String get noActiveNetworkConnections =>
      'Không có kết nối mạng đang hoạt động';
  @override
  String get useAddButtonToAddConnection => 'Dùng nút (+) để thêm kết nối mới';
  @override
  String get unknownConnection => 'Kết nối không xác định';
  @override
  String serviceTypeConnection(String serviceName) => 'Kết nối $serviceName';
  @override
  String get noServicesAvailable => 'Không có dịch vụ nào';
  @override
  String get webdavConnections => 'Kết nối WebDAV';
  @override
  String errorOpeningTab(String tabName, String error) =>
      'Lỗi khi mở thẻ cho $tabName: $error';
  @override
  String connectToServiceServer(String serviceName) =>
      'Kết nối đến máy chủ $serviceName';
  @override
  String get serviceType => 'Loại dịch vụ';
  @override
  String get host => 'Máy chủ';
  @override
  String get deleteSavedConnection => 'Xóa kết nối đã lưu';
  @override
  String get username => 'Tên đăng nhập';
  @override
  String get password => 'Mật khẩu';
  @override
  String get portOptional => 'Cổng (tùy chọn)';
  @override
  String get useSslTls => 'Dùng SSL/TLS';
  @override
  String get basePathOptional => 'Đường dẫn gốc (tùy chọn)';
  @override
  String get basePathHint => 'vd: /webdav';
  @override
  String get domainOptional => 'Tên miền (tùy chọn)';
  @override
  String get saveCredentials => 'Lưu thông tin đăng nhập';
  @override
  String get saveCredentialsDescription =>
      'Lưu thông tin đăng nhập cho các lần kết nối sau';
  @override
  String get deleteSavedConnectionTitle => 'Xóa kết nối đã lưu?';
  @override
  String deleteSavedConnectionConfirm(String host) =>
      'Bạn có chắc muốn xóa kết nối đã lưu cho "$host"?';
  @override
  String connectionDeleted(String host) => 'Đã xóa kết nối cho "$host".';
  @override
  String connectionNotFoundToDelete(String host) =>
      'Không tìm thấy kết nối cho "$host" để xóa.';
  @override
  String get errorDeletingConnection => 'Lỗi khi xóa kết nối';
  @override
  String connectionFailed(String error) => 'Kết nối thất bại: $error';
  @override
  String get networkConnection => 'Kết nối mạng';
  @override
  String get notConnected => 'Chưa kết nối';
  @override
  String get refreshSmbVersionInfo => 'Làm mới thông tin phiên bản SMB';
  @override
  String shareLabel(String sharePath) => 'Chia sẻ: $sharePath';
  @override
  String get rootShare => 'Chia sẻ gốc';
  @override
  String foundDevicesCount(int count) => 'Tìm thấy $count thiết bị';
  @override
  String get noWebdavConnections => 'Không có kết nối WebDAV.';
  @override
  String get addConnectionOrSampleToStart =>
      'Thêm kết nối mới hoặc kết nối mẫu để bắt đầu.';
  @override
  String get addSample => 'Thêm mẫu';
  @override
  String get editWebdavConnection => 'Chỉnh sửa kết nối WebDAV';
  @override
  String get update => 'Cập nhật';
  @override
  String get connectionUpdatedSuccess => 'Đã cập nhật kết nối thành công';
  @override
  String get failedToUpdateConnection => 'Cập nhật kết nối thất bại';
  @override
  String get deleteConnection => 'Xóa kết nối';
  @override
  String deleteConnectionConfirm(String host) =>
      'Bạn có chắc muốn xóa kết nối đến "$host"?';
  @override
  String get connectionDeletedSuccess => 'Đã xóa kết nối thành công';
  @override
  String get failedToDeleteConnection => 'Xóa kết nối thất bại';
  @override
  String get addSampleWebdavConnection => 'Thêm kết nối WebDAV mẫu';
  @override
  String get sampleConnectionAddedSuccess => 'Đã thêm kết nối mẫu thành công';
  @override
  String get failedToAddSampleConnection => 'Thêm kết nối mẫu thất bại';
  @override
  String lastConnected(String dateStr) => 'Kết nối lần cuối: $dateStr';
  @override
  String get editConnection => 'Chỉnh sửa kết nối';
  @override
  String get closeConnection => 'Đóng kết nối';
  @override
  String get retry => 'Thử lại';
  @override
  String get networkErrorPersistsHint =>
      'Nếu lỗi vẫn xảy ra, hãy kiểm tra kết nối mạng và trạng thái máy chủ.';
  @override
  String get pleaseEnterHost => 'Vui lòng nhập máy chủ';
  @override
  String get pleaseEnterPort => 'Vui lòng nhập cổng';
  @override
  String get pleaseEnterValidPort => 'Vui lòng nhập số cổng hợp lệ';
  @override
  String get connectionMode => 'Chế độ kết nối:';
  @override
  String get passive => 'Thụ động';
  @override
  String get active => 'Chủ động';
  @override
  String get port => 'Cổng';
  @override
  String get basePath => 'Đường dẫn gốc';

  // Drawer menu items
  @override
  String get networksMenu => 'Mạng';

  @override
  String get networkTab => 'Mạng';

  @override
  String get about => 'Giới thiệu';

  // Tab manager
  @override
  String get newTabButton => 'Tab mới';

  @override
  String get openNewTabToStart => 'Mở tab mới để bắt đầu';

  @override
  String get tabManager => 'Quản lý Tab';

  @override
  String get openTabs => 'Tab đang mở';

  @override
  String get noTabsOpen => 'Không có tab nào';

  @override
  String get closeAllTabs => 'Đóng tất cả Tab';

  @override
  String get activeTab => 'Đang mở';

  @override
  String get closeTab => 'Đóng tab';

  @override
  String get addNewTab => 'Thêm tab mới';

  // Desktop windows (tabbed browsing)
  @override
  String get newWindow => 'Cửa sổ mới';

  @override
  String get moveTabToNewWindow => 'Chuyển tab sang cửa sổ mới';

  @override
  String get moveTabToWindow => 'Chuyển tab sang cửa sổ...';

  @override
  String get mergeWindowIntoThis => 'Gộp cửa sổ vào đây...';

  @override
  String get selectWindow => 'Chọn cửa sổ';

  @override
  String get noOtherWindows => 'Không có cửa sổ nào khác';

  // Home screen
  @override
  String get welcomeTitle => 'Chào mừng đến với CB File Hub';

  @override
  String get welcomeSubtitle => 'Trợ lý quản lý tệp mạnh mẽ của bạn';

  @override
  String get quickActionsTip =>
      'Mẹo: Sử dụng các hành động nhanh bên dưới để bắt đầu nhanh chóng';

  @override
  String get quickActionsHome => 'Hành động nhanh';

  @override
  String get startHere => 'Bắt đầu tại đây';

  @override
  String get newTabAction => 'Tab mới';

  @override
  String get newTabActionDesc => 'Mở tab trình duyệt tệp mới';

  @override
  String get tagsAction => 'Thẻ';

  @override
  String get tagsActionDesc => 'Tổ chức với thẻ thông minh';

  @override
  String get imageGalleryTab => 'Thư viện ảnh';

  @override
  String get videoGalleryTab => 'Thư viện video';

  @override
  String get drivesTab => 'Ổ đĩa';

  @override
  String get browseTab => 'Duyệt';

  @override
  String get documentsTab => 'Tài liệu';

  @override
  String get homeTab => 'Trang chủ';

  @override
  String get internalStorage => 'Bộ nhớ trong';

  @override
  String get storagePrefix => 'Bộ nhớ';

  @override
  String get rootFolder => 'Thư mục gốc';

  // Video Hub
  @override
  String get videoHub => 'Thư viện video';

  @override
  String get manageYourVideos => 'Quản lý video của bạn';

  @override
  String get videos => 'Video';

  @override
  String get videoActions => 'Thao tác video';

  @override
  String get allVideos => 'Tất cả video';

  @override
  String get browseAllYourVideos => 'Duyệt tất cả video của bạn';

  @override
  String get videosFolder => 'Thư mục video';

  @override
  String get openFileManager => 'Mở trình quản lý tệp';

  @override
  String get videoStatistics => 'Thống kê video';

  @override
  String get totalVideos => 'Tổng số video';

  // Gallery Hub
  @override
  String get galleryHub => 'Thư viện ảnh';

  @override
  String get managePhotosAndAlbums => 'Quản lý ảnh và album của bạn';

  @override
  String get images => 'Hình ảnh';

  @override
  String get galleryActions => 'Thao tác thư viện';

  @override
  String get quickAccess => 'Truy cập nhanh';

  @override
  String get browseAllYourPictures => 'Duyệt tất cả hình ảnh của bạn';

  @override
  String get browseAllYourPhotos => 'Duyệt tất cả ảnh của bạn';

  @override
  String get organizeInAlbums => 'Tổ chức trong album';

  @override
  String get picturesFolder => 'Thư mục ảnh';

  @override
  String get photosFromCamera => 'Ảnh từ máy ảnh';

  @override
  String get downloadedFiles => 'Tệp đã tải xuống';

  @override
  String get downloadedImages => 'Hình ảnh đã tải xuống';

  @override
  String get featuredAlbums => 'Album nổi bật';

  @override
  String get personalized => 'Cá nhân hóa';

  @override
  String get configureFeaturedAlbums => 'Cấu hình Album nổi bật';

  @override
  String get noFeaturedAlbums => 'Không có Album nổi bật';

  @override
  String get createSomeAlbumsToSeeThemFeaturedHere =>
      'Tạo một số album để xem chúng xuất hiện ở đây';

  @override
  String get removeFromFeatured => 'Xóa khỏi nổi bật';

  @override
  String get galleryStatistics => 'Thống kê thư viện';

  @override
  String get totalImages => 'Tổng số hình ảnh';

  @override
  String get albums => 'Album';

  @override
  String get allImages => 'Tất cả hình ảnh';

  @override
  String get camera => 'Máy ảnh';

  @override
  String get downloads => 'Tải xuống';

  @override
  String get recent => 'Gần đây';

  @override
  String get folders => 'Thư mục';

  // Video player screenshot
  @override
  String get takeScreenshot => 'Chụp màn hình';

  @override
  String get screenshotSaved => 'Đã lưu ảnh chụp màn hình';

  @override
  String get screenshotSavedAt => 'Ảnh chụp màn hình đã lưu tại';

  @override
  String get screenshotFailed => 'Không thể lưu ảnh chụp màn hình';

  @override
  String get screenshotSavedToFolder =>
      'Đã lưu ảnh chụp màn hình vào thư mục Screenshots';

  @override
  String get openScreenshotFolder => 'Mở thư mục';

  @override
  String get viewScreenshot => 'Xem';

  @override
  String get screenshotNotAvailableVlc => 'Chụp màn hình không khả dụng';

  @override
  String get screenshotNotAvailableVlcMessage =>
      'Chụp ảnh màn hình không khả dụng với VLC player.\nVui lòng chuyển sang Media Kit player trong cài đặt.';

  @override
  String get screenshotFileNotFound => 'Không tìm thấy file ảnh';

  @override
  String get screenshotCannotOpenTab =>
      'Không thể mở tab thư mục trong ngữ cảnh này';

  @override
  String get screenshotErrorOpeningFolder => 'Lỗi mở thư mục';

  @override
  String get closeAction => 'Đóng';

  // Video library
  @override
  String get videoLibrary => 'Thư Viện Video';

  @override
  String get videoLibraries => 'Thư Viện Video';

  @override
  String get createVideoLibrary => 'Tạo Thư Viện Video';

  @override
  String get editVideoLibrary => 'Chỉnh Sửa Thư Viện';

  @override
  String get deleteVideoLibrary => 'Xóa Thư Viện Video';

  @override
  String get addVideoSource => 'Thêm Nguồn Video';

  @override
  String get removeVideoSource => 'Xóa Nguồn';

  @override
  String get videoSources => 'Nguồn Video';

  @override
  String get noVideoSources => 'Chưa có nguồn video nào';

  @override
  String get filterByTags => 'Lọc Theo Thẻ';

  @override
  String get clearTagFilter => 'Xóa Bộ Lọc';

  @override
  String get recentVideos => 'Video Gần Đây';

  @override
  String get videoHubTitle => 'Trung Tâm Video';

  @override
  String get videoHubWelcome => 'Quản lý thư viện video của bạn';

  @override
  String get manageVideoLibraries => 'Quản Lý Thư Viện Video';

  @override
  String get videoCount => 'Số Lượng Video';

  @override
  String get scanForVideos => 'Quét Video';

  @override
  String get rescanLibrary => 'Quét Lại Thư Viện';

  @override
  String deleteVideoLibraryConfirmation(String name) =>
      'Xóa thư viện video "$name"?';

  @override
  String get libraryDeletedSuccessfully => 'Đã xóa thư viện thành công';

  @override
  String get sourceAdded => 'Đã thêm nguồn thành công';

  @override
  String get sourceRemoved => 'Đã xóa nguồn thành công';

  @override
  String get selectVideoSource => 'Chọn Thư Mục Nguồn Video';

  @override
  String get videoLibrarySettings => 'Cài Đặt Thư Viện Video';

  @override
  String get manageVideoSources => 'Quản Lý Nguồn Video';

  @override
  String get videoExtensions => 'Định Dạng Video';

  @override
  String get includeSubdirectories => 'Bao Gồm Thư Mục Con';

  @override
  String get noVideosInLibrary => 'Chưa có video trong thư viện này';

  @override
  String get libraryCreatedSuccessfully => 'Đã tạo thư viện thành công';

  @override
  String videoLibraryCount(int count) => '$count thư viện';

  // Streaming and download dialogs
  @override
  String openFileTypeFile(String fileType) => 'Mở tệp $fileType';
  @override
  String streamDownloadPrompt(String fileType) =>
      'Loại tệp $fileType không hỗ trợ phát trực tuyến. Bạn có muốn tải xuống thiết bị không?';
  @override
  String get downloadingFile => 'Đang tải tệp...';
  @override
  String get fileDownloadedSuccess => 'Đã tải tệp thành công';
  @override
  String get errorDownloadingFile => 'Lỗi khi tải tệp';
  @override
  String get errorTitle => 'Lỗi';
  @override
  String get mediaPlaybackError => 'Lỗi phát media';
  @override
  String mediaPlaybackErrorVlcContent(String error) =>
      'Không thể phát file với VLC Direct SMB:\n\n$error\n\nVui lòng kiểm tra:\n• Kết nối SMB\n• Đường dẫn file\n• Quyền truy cập file';
  @override
  String mediaPlaybackErrorNativeContent(String error) =>
      'Không thể phát file với Native VLC Direct SMB:\n\n$error\n\nVui lòng kiểm tra:\n• Kết nối SMB\n• Đường dẫn file\n• Quyền truy cập file\n• Tính khả dụng của Native SMB client';
  @override
  String get chooseAnotherApp => 'Chọn ứng dụng khác...';
  @override
  String get folderProperties => 'Thuộc tính thư mục';
  @override
  String get createNewFolder => 'Tạo thư mục mới';
  @override
  String get createNewFile => 'Tạo tệp mới';
  @override
  String get folderPropertyPath => 'Đường dẫn';
  @override
  String get folderPropertyCreated => 'Tạo lúc';
  @override
  String get folderPropertyContent => 'Nội dung';
  @override
  String get folderPropertySizeDirectChildren =>
      'Kích thước (thư mục con trực tiếp)';
  @override
  String get networkServiceNotAvailable => 'Dịch vụ mạng không khả dụng';
  @override
  String get folderNameLabel => 'Tên thư mục';
  @override
  String get fileNameLabel => 'Tên tệp';
  @override
  String errorCreatingFile(String error) => 'Lỗi tạo tệp: $error';
}
