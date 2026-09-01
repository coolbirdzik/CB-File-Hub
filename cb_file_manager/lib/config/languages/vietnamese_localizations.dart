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
  @override
  String get thirdPartyApps => 'Ứng dụng bên thứ ba';
  @override
  String get configureContextMenu => 'Tùy chỉnh menu ngữ cảnh';
  @override
  String get contextMenuLayout => 'Bố cục menu ngữ cảnh';
  @override
  String get contextMenuLayoutDescription =>
      'Sắp xếp hoặc ẩn các lệnh hiện khi nhấp chuột phải';
  @override
  String get contextMenuLayoutHint =>
      'Kéo các lệnh để đổi thứ tự. Lệnh đã ẩn vẫn có thể bật lại tại đây.';
  @override
  String get contextMenuForFiles => 'Tệp';
  @override
  String get contextMenuForFolders => 'Thư mục';
  @override
  String get contextMenuForMultipleItems => 'Nhiều mục';
  @override
  String get resetContextMenuLayout => 'Đặt lại bố cục';
  @override
  String get contextMenuLayoutReset => 'Đã đặt lại bố cục menu ngữ cảnh';

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
  String get setCoolBirdAsDefaultForArchives =>
      'Đặt CB File Hub làm mặc định cho tệp nén';
  @override
  String get setCoolBirdAsDefaultForArchivesSuccess =>
      'CB File Hub đã là ứng dụng mặc định cho tệp nén.';
  @override
  String get setCoolBirdAsDefaultForArchivesFailed =>
      'Không thể đặt CB File Hub làm mặc định cho tệp nén.';
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
  String get manage => 'Quản lý';
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
  String get viewModeColumns => 'Cột';

  @override
  String get viewModeTree => 'Cây';

  @override
  String get viewModeTiles => 'Thẻ';

  @override
  String get previewPaneTitle => 'Xem trước';

  @override
  String get previewSelectFile => 'Chọn tệp để xem trước';

  @override
  String get previewNotSupported => 'Chưa hỗ trợ xem trước loại tệp này';

  @override
  String get archiveSectionTitle => 'Tệp nén';

  @override
  String get archiveBrowseTitle => 'Xem nội dung';

  @override
  String get archiveExtractHere => 'Giải nén tại đây';

  @override
  String get archiveExtractTo => 'Giải nén vào…';

  @override
  String get archiveExtractToTitle => 'Chọn thư mục giải nén';

  @override
  String get archiveExtractAll => 'Giải nén tất cả';

  @override
  String get archiveExtracting => 'Đang giải nén…';

  @override
  String get archiveExtractComplete => 'Giải nén xong';

  @override
  String archiveExtractFailed(String error) => 'Giải nén thất bại: $error';

  @override
  String get archiveEmpty => 'Tệp nén trống';

  @override
  String archivePreviewSummary(int count) => '$count mục';

  @override
  String archivePreviewMore(int count) => '… và $count mục nữa';

  @override
  String get previewUnavailable => 'Không thể xem trước';

  @override
  String get previewTextTruncated => 'Hiển thị một phần nội dung';

  @override
  String get previewTextTooLarge => 'Tệp quá lớn để xem trước';

  @override
  String get showPreview => 'Hiện xem trước';

  @override
  String get hidePreview => 'Ẩn xem trước';

  // Column names
  @override
  String get columnName => 'Tên';

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

  @override
  String get columnDateAccessed => 'Ngày truy cập';

  @override
  String get columnExtension => 'Phần mở rộng';

  @override
  String get columnPath => 'Đường dẫn';

  @override
  String get columnTags => 'Nhãn';

  @override
  String get columnDimensions => 'Kích thước ảnh';

  @override
  String get columnDuration => 'Thời lượng';

  @override
  String get columnItemCount => 'Số mục';

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

  @override
  String get columnDateAccessedDescription =>
      'Hiển thị ngày giờ truy cập tệp lần cuối';

  @override
  String get columnExtensionDescription =>
      'Hiển thị phần mở rộng tệp (ví dụ: .mp4, .docx)';

  @override
  String get columnPathDescription => 'Hiển thị đường dẫn tương đối của tệp';

  @override
  String get columnTagsDescription => 'Hiển thị nhãn của tệp';

  @override
  String get columnDimensionsDescription =>
      'Hiển thị kích thước ảnh/video (rộng x cao)';

  @override
  String get columnDurationDescription =>
      'Hiển thị thời lượng cho tệp video/âm thanh';

  @override
  String get columnItemCountDescription =>
      'Hiển thị số lượng mục trong thư mục';

  // Column visibility dialog
  @override
  String get columnVisibilityInstructions =>
      'Chọn các cột bạn muốn hiển thị trong chế độ xem chi tiết. '
      'Cột "Tên" luôn được hiển thị và không thể tắt.';

  // List field visibility
  @override
  String get listFieldVisibilityTitle => 'Tùy chỉnh trường hiển thị';

  @override
  String get listFieldVisibilityInstructions =>
      'Chọn các trường bạn muốn hiển thị trong chế độ xem danh sách.';

  // Metadata format strings
  @override
  String dimensionsFormat(int width, int height) => '$width \u00D7 $height';

  @override
  String itemCountFormat(int count) => '$count mục';

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
  String get selectMultipleTags => 'Chọn nhiều thẻ';

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

  // File template type names
  @override
  String get fileTypeMarkdown => 'Markdown';
  @override
  String get fileTypeJson => 'Tệp JSON';
  @override
  String get fileTypeHtml => 'Tài liệu HTML';
  @override
  String get fileTypeCss => 'Trang định kiểu CSS';
  @override
  String get fileTypeDart => 'Tệp Dart';
  @override
  String get fileTypePython => 'Script Python';
  @override
  String get fileTypeJavaScript => 'JavaScript';
  @override
  String get fileTypeTypeScript => 'TypeScript';
  @override
  String get fileTypeJava => 'Tệp Java';
  @override
  String get fileTypeCpp => 'Tệp C++';
  @override
  String get fileTypeC => 'Tệp C';
  @override
  String get fileTypeGo => 'Tệp Go';
  @override
  String get fileTypeRust => 'Tệp Rust';
  @override
  String get fileTypeXml => 'Tệp XML';
  @override
  String get fileTypeYaml => 'Tệp YAML';
  @override
  String get fileTypeShell => 'Script Shell';
  @override
  String get fileTypeCsv => 'Bảng tính CSV';
  @override
  String get fileTypeLibreDoc => 'Tài liệu LibreOffice';
  @override
  String get fileTypeLibreSheet => 'Bảng tính LibreOffice';
  @override
  String get fileTypeLibrePresentation => 'Bài thuyết trình LibreOffice';
  @override
  String get fileTypeLibreDraw => 'Bản vẽ LibreOffice';
  @override
  String get fileTypeLibreChart => 'Biểu đồ LibreOffice';
  @override
  String get fileTypeLibreFormula => 'Công thức LibreOffice';
  @override
  String get fileTypeWpsDoc => 'Tài liệu WPS';
  @override
  String get fileTypeWpsSheet => 'Bảng tính WPS';
  @override
  String get fileTypeWpsPresentation => 'Bài thuyết trình WPS';
  @override
  String get fileTypeGoogleDoc => 'Google Doc';
  @override
  String get fileTypeGoogleSheet => 'Google Sheet';
  @override
  String get fileTypeGoogleSlides => 'Google Slides';
  @override
  String get fileTypeTar => 'Tệp nén TAR';
  @override
  String get fileTypeGzip => 'Tệp nén GZIP';

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
  String get accentColor => 'Màu nhấn';
  @override
  String currentAccentColor(String name) => 'Màu nhấn hiện tại: $name';
  @override
  String get fontColor => 'Màu chữ';
  @override
  String currentFontColor(String name) => 'Màu chữ hiện tại: $name';
  @override
  String get uiFont => 'Phông chữ';
  @override
  String currentUiFont(String name) => 'Phông chữ hiện tại: $name';
  @override
  String get uiFontUnicodeHint =>
      'Font miễn phí, hỗ trợ Unicode (tiếng Việt + Latin mở rộng). Font bổ sung tải một lần rồi lưu máy.';
  @override
  String get backdropMode => 'Chế độ nền';
  @override
  String get backdropModeDynamic => 'Động';
  @override
  String get backdropModeWallpaper => 'Hình nền';
  @override
  String get backdropModeDynamicDescription =>
      'Dùng nền acrylic động của hệ thống.';
  @override
  String get backdropModeWallpaperDescription =>
      'Dùng hình nền máy tính làm nền ứng dụng.';
  @override
  String get noSystemWallpaperDetected => 'Không tìm thấy hình nền hệ thống';
  @override
  String get customBackdropImage => 'Tùy chọn';
  @override
  String get backdropImageNotFound => 'Không tìm thấy ảnh';
  @override
  String get desktopAcrylicStrength => 'Độ mạnh acrylic máy tính';
  @override
  String desktopAcrylicStrengthDescription(int percentage) =>
      'Điều chỉnh độ mờ và độ đậm nền máy tính ($percentage%).';
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
  @override
  String get failedToCreateAlbum => 'Không thể tạo album';
  @override
  String get failedToUpdateAlbum => 'Không thể cập nhật album';

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
  String get treeViewMode => 'Chế độ cây';
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
  String get setThumbnail => 'Đặt ảnh thu nhỏ';
  @override
  String get manageHierarchy => 'Quản lý phân cấp';
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
  String get selectFilesToRemoveTags => 'Vui lòng chọn tệp để xóa thẻ';
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
  @override
  String get tagManagementInfoTitle => 'Thông tin quản lý thẻ';
  @override
  String get tagManagementInfoDescription =>
      'Màn hình này cho phép bạn quản lý các thẻ cho tệp và thư mục.\n\n'
      '• Xem tất cả thẻ\n'
      '• Tìm kiếm thẻ\n'
      '• Sắp xếp thẻ theo tên hoặc độ phổ biến\n'
      '• Xem các tệp được gắn thẻ';
  @override
  String removeTagsFromFilesTitle(int count) => 'Xóa thẻ khỏi $count tệp';
  @override
  String get loadingTags => 'Đang tải thẻ...';
  @override
  String get noCommonTagsAcrossSelectedFiles =>
      'Không có thẻ chung nào giữa các tệp đã chọn';
  @override
  String removeTagsSuccess(int removedTagCount, int fileCount) =>
      'Đã xóa $removedTagCount thẻ khỏi $fileCount tệp';
  @override
  String removeTagsError(String error) => 'Lỗi khi xóa thẻ: $error';
  @override
  String batchTagProcessingError(String error) => 'Lỗi khi xử lý thẻ: $error';
  @override
  String searchError(String error) => 'Lỗi tìm kiếm: $error';

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
  String get syncToCloudSuccess => 'Đã đồng bộ lên đám mây thành công';
  @override
  String get syncToCloudFailed => 'Không thể đồng bộ lên đám mây';
  @override
  String get syncFromCloudSuccess => 'Đã đồng bộ từ đám mây thành công';
  @override
  String get syncFromCloudFailed => 'Không thể đồng bộ từ đám mây';
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
  @override
  String get backupAndRestore => 'Sao lưu & Khôi phục';
  @override
  String get backupRestoreHint =>
      'Sao lưu thẻ và cài đặt vào file .db (nhanh, mở rộng được), hoặc xuất cài đặt ra JSON (đọc được bằng văn bản).';
  @override
  String get exportSqlite => 'Xuất SQLite';
  @override
  String get exportSqliteDesc => 'Sao lưu nhanh (.db) — thẻ + cài đặt';
  @override
  String get exportJson => 'Xuất JSON';
  @override
  String get exportJsonDesc => 'Xuất cài đặt ra JSON có thể đọc được';
  @override
  String get importBackup => 'Nhập bản sao lưu';
  @override
  String get importBackupDesc => 'Tự động nhận diện file .db hoặc .json';
  @override
  String get exporting => 'Đang xuất...';
  @override
  String get importing => 'Đang nhập...';
  @override
  String get sharedPreferences => 'SharedPreferences';
  @override
  String get sharedPreferencesDesc =>
      'Xem và xóa cài đặt ứng dụng dạng key-value';
  @override
  String get clearSharedPreferencesConfirm => 'Xóa toàn bộ SharedPreferences?';
  @override
  String get deleteKeyConfirm => 'Xóa key này?';
  @override
  String get clear => 'Xóa';
  @override
  String get sharedPreferencesCleared => 'Đã xóa SharedPreferences.';
  @override
  String get deletedKey => 'Đã xóa: ';
  @override
  String get copied => 'Đã sao chép: ';
  @override
  String tagsImported(int count) => '$count thẻ đã nhập';
  @override
  String settingsRestored(int count) => '$count cài đặt đã khôi phục';
  @override
  String get saveBackup => 'Lưu bản sao lưu';
  @override
  String get exportPreferencesAsJson => 'Xuất cài đặt ra JSON';
  @override
  String get sharedPreferencesKeyRemoved =>
      'Đã xóa cài đặt khỏi SharedPreferences.';
  @override
  String get jsonCopiedToClipboard => 'Đã sao chép JSON vào bảng nhớ tạm';
  @override
  String get copyValue => 'Sao chép giá trị';
  @override
  String get deleteKey => 'Xóa key';
  @override
  String get copyJson => 'Sao chép JSON';
  @override
  String get viewJson => 'Xem JSON';
  @override
  String get clearAll => 'Xóa tất cả';

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
  String get seekSpeed => 'Tốc độ tua video';
  @override
  String get seekSpeedDescription =>
      'Tốc độ nhảy video khi giữ phím tua hoặc nhấn giữ trên thiết bị di động';
  @override
  String get seekSpeedSlow => 'Chậm';
  @override
  String get seekSpeedMedium => 'Vừa';
  @override
  String get seekSpeedFast => 'Nhanh';
  @override
  String get openVideoInNewWindow => 'Mở video ở cửa sổ riêng';
  @override
  String get openVideoInNewWindowDescription =>
      'Chỉ trên desktop. Dùng một cửa sổ trình phát riêng; khi mở video khác, video trong cửa sổ đó sẽ được thay thế.';
  @override
  String get openVideoInNewWindowEnabled =>
      'Video sẽ mở trong một cửa sổ trình phát riêng';
  @override
  String get openVideoInNewWindowDisabled =>
      'Trình phát video sẽ mở trong cửa sổ hiện tại';
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
  String get cropImage => 'Cắt ảnh';
  @override
  String get applyCrop => 'Áp dụng';
  @override
  String get useOriginal => 'Dùng ảnh gốc';
  @override
  String get aspectFree => 'Tự do';
  @override
  String get tagGridCropRecommendation =>
      'Gợi ý cho card tag dạng grid: 16:9, tối thiểu 1280 × 720 px';
  @override
  String get tagGridAspectPreset => '16:9 · Grid tag';
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
  @override
  String get viewModeFeatureComingSoon =>
      'Chức năng chuyển chế độ xem sẽ được thêm sau';
  @override
  String get cannotCreateFileInThisLocation => 'Không thể tạo tệp ở vị trí này';

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
  String bulkDeleteSuccess(int count) => 'Đã xóa thành công $count thẻ';

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
  String get globalSearchModeEnabled => 'Đã chuyển sang tìm trong thư mục con';

  @override
  String get localSearchModeEnabled =>
      'Đã chuyển sang tìm kiếm thư mục hiện tại';

  @override
  String get globalSearchMode => 'Đang tìm trong thư mục con (nhấn để chuyển)';

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
  String get globalSearch => 'Tìm trong thư mục con';

  @override
  String get searchByNameOrTag => 'Tìm theo tên hoặc #tag';

  @override
  String get searchInSubfolders => 'Tìm trong thư mục con';

  @override
  String get featureNotImplemented => 'Tính năng sẽ được thêm sau';

  @override
  String get searchInAllFolders =>
      'Tìm trong thư mục hiện tại và các thư mục con';

  @override
  String get searchInCurrentFolder => 'Chỉ tìm trong thư mục hiện tại';

  @override
  String get searchShortcuts => 'Phím tắt';

  @override
  String get regexMode => 'Chế độ Regex';

  @override
  String get regexModeEnabled => 'Đã bật chế độ Regex';

  @override
  String get regexModeDisabled => 'Đã tắt chế độ Regex';

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
      'Bấm vào biểu tượng thư mục/toàn cầu để chuyển giữa chỉ tìm trong thư mục hiện tại và tìm cả các thư mục con.';

  @override
  String get regexSearchDesc =>
      'Bật chế độ Regex ({ }) để khớp tên bằng biểu thức chính quy.\n'
      'Ví dụ cơ bản:\n'
      '• Bắt đầu bằng "img_": ^img_.*\n'
      '• Kết thúc bằng .mp4: .*\\.mp4\$\n'
      '• Chứa "invoice": .*invoice.*\n'
      '• Đúng 4 chữ số: ^\\d{4}\$\n'
      '• File report theo năm: ^report_\\d{4}\\.pdf\$';

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
  String get fileThumbnailFit => 'Cách hiển thị thumbnail file';

  @override
  String get fileThumbnailFitDescription =>
      'Chọn thumbnail phủ đầy khung hoặc hiển thị toàn bộ ảnh';

  @override
  String get tagThumbnailFit => 'Cách hiển thị thumbnail tag';

  @override
  String get tagThumbnailFitDescription =>
      'Chọn hiển thị toàn bộ ảnh hoặc phủ đầy khung thumbnail tag';

  @override
  String get thumbnailFitContain => 'Hiển thị toàn bộ ảnh';

  @override
  String get thumbnailFitCover => 'Phủ đầy khung';

  @override
  String get rememberTabWorkspace => 'Ghi nhớ không gian làm việc tab';

  @override
  String get rememberTabWorkspaceDescription =>
      'Khôi phục tab mở gần nhất và ghi nhớ trạng thái thu gọn của drawer theo từng tab.';

  @override
  String get tabInactiveThreshold => 'Thời gian tab không hoạt động';

  @override
  String get tabInactiveThresholdDescription =>
      'Tự động tạm dừng tab và giải phóng bộ nhớ cache sau khoảng thời gian không sử dụng. Chọn "Tắt" để giữ tab luôn hoạt động.';

  @override
  String get tabInactiveThresholdDisabled => 'Tắt';

  @override
  String get tabInactiveThresholdMinutesValue => 'phút';

  @override
  String get tabInactiveThresholdHoursValue => 'giờ';

  @override
  String get cacheManagement => 'Quản lý bộ nhớ cache';

  @override
  String get cacheManagementDescription =>
      'Xóa dữ liệu cache để giải phóng bộ nhớ';

  @override
  String get appDataManagement => 'Quản lý dữ liệu ứng dụng';

  @override
  String get appDataManagementDescription =>
      'Xem và xóa dữ liệu cache và dữ liệu đã lưu của ứng dụng';

  @override
  String get documentsData => 'Dữ liệu đã lưu';

  @override
  String get documentsDataDescription =>
      'Các tệp lưu bền trong Documents, không bị xóa khi dọn cache';

  @override
  String get tagThumbnails => 'Ảnh thu nhỏ của thẻ';

  @override
  String get tagThumbnailsDescription =>
      'Ảnh bạn chọn làm ảnh thu nhỏ cho thẻ (khung hình trích từ video)';

  @override
  String get clearTagThumbnails => 'Xóa ảnh thu nhỏ của thẻ';

  @override
  String get tagThumbnailsCleared => 'Đã xóa ảnh thu nhỏ của thẻ';

  @override
  String get documentsRoot => 'Thư mục Documents';

  @override
  String get cacheFolder => 'Thư mục cache:';

  @override
  String get networkThumbnails => 'Thumbnail mạng:';

  @override
  String get videoThumbnailsCache => 'Thumbnail video:';

  @override
  String get tempFiles => 'File tạm:';

  @override
  String get videoLibraryCache => 'Cache thư viện video:';

  @override
  String get clearVideoLibraryCache => 'Xóa cache thư viện video';

  @override
  String get videoLibraryCacheCleared => 'Đã xóa cache thư viện video';

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
  @override
  String get allowFileExtensionRename => 'Cho phép sửa phần mở rộng tệp';

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
  @override
  String get columnDateDeleted => 'Ngày xóa';
  @override
  String get columnOriginalPath => 'Đường dẫn gốc';
  @override
  String get askCbAgentAboutThisFile => 'Hỏi CB Agent về tệp này';
  @override
  String get askCbAgentAboutThisFolder => 'Hỏi CB Agent về thư mục này';

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
  String get driveGroupFixed => 'Máy tính này';
  @override
  String get driveGroupRemovable => 'Ổ tháo lắp';
  @override
  String get driveGroupNetwork => 'Mạng';
  @override
  String get driveGroupOther => 'Khác';
  @override
  String get driveTapToBrowse => 'Chạm để duyệt';
  @override
  String get driveRestrictedAccess => 'Truy cập bị hạn chế';
  @override
  String get driveEject => 'Đẩy ra';
  @override
  String get driveEjectConfirmTitle => 'Đẩy ổ đĩa ra?';
  @override
  String driveEjectConfirmMessage(String name) =>
      'Gỡ an toàn "$name"? Hãy đảm bảo không có tệp nào đang được dùng.';
  @override
  String get driveEjectSuccess => 'Đã đẩy ổ đĩa ra';
  @override
  String driveEjectFailed(String error) => 'Không thể đẩy ra: $error';
  @override
  String get driveRename => 'Đổi tên';
  @override
  String get driveRenameTitle => 'Đổi tên volume';
  @override
  String get driveRenameHint => 'Nhãn volume';
  @override
  String get driveRenameSuccess => 'Đã đổi tên volume';
  @override
  String driveRenameFailed(String error) => 'Không thể đổi tên: $error';
  @override
  String get driveFormatConfirmTitle => 'Định dạng ổ đĩa?';
  @override
  String driveFormatConfirmMessage(String name) =>
      'Mở công cụ định dạng hệ thống cho "$name"? Thao tác có thể xóa toàn bộ dữ liệu trên volume.';
  @override
  String get driveOpenInCleaner => 'Mở trong Disk Cleaner';
  @override
  String get driveUsed => 'Đã dùng';
  @override
  String get driveFree => 'Còn trống';
  @override
  String get driveTotal => 'Tổng';
  @override
  String get driveType => 'Loại';
  @override
  String get driveFilesystem => 'Hệ thống tệp';
  @override
  String get driveSerial => 'Serial';
  @override
  String get driveKindFixed => 'Ổ đĩa cục bộ';
  @override
  String get driveKindRemovable => 'Ổ tháo lắp';
  @override
  String get driveKindNetwork => 'Mạng';
  @override
  String get driveKindOptical => 'Ổ quang';
  @override
  String get driveKindRam => 'Ổ RAM';
  @override
  String get driveKindInternal => 'Bộ nhớ trong';
  @override
  String get driveKindUnknown => 'Lưu trữ';
  @override
  String get openInNewPane => 'Mở trong khung mới';
  @override
  String get openInWindowsTerminal => 'Mở trong Windows Terminal';
  @override
  String get driveCleanup => 'Dọn dẹp';
  @override
  String get driveFormat => 'Định dạng';
  @override
  String get driveBitLocker => 'Bật BitLocker';
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
  String itemsCount(int count) => '$count mục';
  @override
  String get noActiveTab => 'Không có tab hoạt động';
  @override
  String get masonryLayoutName => 'Bố cục Masonry (Pinterest)';
  @override
  String get undo => 'Hoàn tác';
  @override
  String errorWithMessage(String message) => 'Lỗi: $message';
  @override
  String get referencedFile => 'Tệp được tham chiếu';
  @override
  String referencedFiles(int count) => '$count tệp được tham chiếu';
  @override
  String pathsCopied(int count) => 'Đã sao chép $count đường dẫn';
  @override
  String get moveToTrashTitle => 'Chuyển vào thùng rác';
  @override
  String get imageMovedToTrash => 'Đã chuyển ảnh vào thùng rác';
  @override
  String get failedToMoveImageToTrash => 'Không thể chuyển ảnh vào thùng rác';
  @override
  String failedToMoveImageToTrashWithError(String error) =>
      'Không thể chuyển ảnh vào thùng rác: $error';
  @override
  String get copiedPathToClipboard => 'Đã sao chép đường dẫn';
  @override
  String get unableToOpenWithExternalApp =>
      'Không thể mở bằng ứng dụng bên ngoài';
  @override
  String failedToDisplayImageInformation(String error) =>
      'Không thể hiển thị thông tin ảnh: $error';
  @override
  String removedFromAlbum(int count) =>
      'Đã gỡ $count ${count == 1 ? 'ảnh' : 'ảnh'} khỏi album';
  @override
  String get addingFilesInBackground => 'Đang thêm tệp ở nền...';
  @override
  String addedFilesProgress(int added, int total) =>
      'Đã thêm $added trên tổng $total tệp';
  @override
  String get filesAddedSuccessfully => 'Đã thêm tệp thành công';

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
  String get closeOtherTabs => 'Đóng các tab khác';

  @override
  String get markTabInactive => 'Đánh dấu không hoạt động';

  @override
  String get restoringTab => 'Đang khôi phục tab…';

  @override
  String get keepTabAlwaysActive => 'Giữ tab luôn hoạt động';

  @override
  String get allowTabAutoSuspend => 'Cho phép tab tự tạm dừng';

  @override
  String get tabAlwaysActiveTooltip => 'Luôn hoạt động';

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
  String get thisPC => 'Máy tính này';

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

  @override
  String get pipOverlayEnabled => 'Đã bật PiP overlay trong ứng dụng';

  @override
  String get pipAndroidEnableFailed => 'Không thể bật PiP trên Android';

  @override
  String pipError(String error) => 'Lỗi PiP: $error';

  @override
  String get pipNoSource => 'Không có nguồn video để mở PiP';

  @override
  String get pipOpenedInSeparateWindow => 'Đã mở PiP ở cửa sổ riêng';

  @override
  String get pipNotSupportedOnPlatform => 'PiP chưa hỗ trợ trên nền tảng này';

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

  @override
  String get libraryCover => 'Ảnh Bìa Thư Viện';

  @override
  String get changeCoverImage => 'Đổi Ảnh Bìa';

  @override
  String get removeCoverImage => 'Xóa Ảnh Bìa';

  @override
  String get coverImageUpdated => 'Đã cập nhật ảnh bìa';

  @override
  String get coverImageRemoved => 'Đã xóa ảnh bìa';

  @override
  String get coverImageUpdateFailed => 'Không thể cập nhật ảnh bìa';

  @override
  String get lastScanLabel => 'Quét lần cuối';

  @override
  String get neverScanned => 'Chưa quét lần nào';

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
  @override
  String get noFileSelectedForBenchmarking => 'Chưa chọn tệp để đo hiệu năng';
  @override
  String benchmarkError(String error) => 'Lỗi benchmark: $error';
  @override
  String benchmarkFailed(String error) => 'Benchmark thất bại: $error';
  @override
  String get saveTagToLocalDatabaseFailed =>
      'Không thể lưu thẻ vào cơ sở dữ liệu cục bộ';
  @override
  String saveTagFailed(String error) => 'Không thể lưu thẻ: $error';
  @override
  String debugTagsSeeded(int savedCount, int requestedCount) =>
      'Đã tạo dữ liệu mẫu $savedCount/$requestedCount thẻ';
  @override
  String debugTagsSeedFailed(String error) => 'Lỗi tạo dữ liệu thẻ: $error';
  @override
  String get debugTagsCleared => 'Đã xóa toàn bộ thẻ';
  @override
  String debugTagsClearFailed(String error) => 'Lỗi xóa toàn bộ thẻ: $error';
  @override
  String addFolderToAlbumFailed(String error) => 'Lỗi thêm thư mục: $error';
  @override
  String addFilesToAlbumFailed(String error) => 'Lỗi thêm tệp: $error';
  @override
  String loadRulesFailed(String error) => 'Lỗi tải rule: $error';
  @override
  String openTerminalFailed(String error) => 'Không thể mở terminal: $error';
  @override
  String startCleanupFailed(String error) =>
      'Không thể khởi động dọn dẹp: $error';
  @override
  String startFormatFailed(String error) =>
      'Không thể khởi động định dạng ổ đĩa: $error';
  @override
  String foundResultsWithTag(int count, String tag) =>
      'Đã tìm thấy $count kết quả với tag "$tag"';

  // AI Agent
  @override
  String get aiSearchAgent => 'Trợ lý AI tìm kiếm';
  @override
  String get aiSearchAgentDescription =>
      'Cấu hình nhà cung cấp AI để tìm kiếm tệp thông minh';
  @override
  String get aiProvider => 'Nhà cung cấp AI';
  @override
  String get aiProviders => 'Nhà cung cấp AI';
  @override
  String get addProvider => 'Thêm nhà cung cấp';
  @override
  String get editProvider => 'Sửa nhà cung cấp';
  @override
  String get deleteProvider => 'Xóa nhà cung cấp';
  @override
  String get providerPreset => 'Mẫu nhà cung cấp';
  @override
  String get selectProviderPreset => 'Chọn mẫu nhà cung cấp';
  @override
  String get providerName => 'Tên nhà cung cấp';
  @override
  String get apiType => 'Loại API';
  @override
  String get authMode => 'Xác thực';
  @override
  String get defaultModel => 'Mô hình mặc định';
  @override
  String get apiKey => 'Khóa API';
  @override
  String get codexOauth => 'Codex OAuth';
  @override
  String get endpointUrl => 'URL Endpoint';
  @override
  String get modelName => 'Tên mô hình';
  @override
  String get openAiCompatible => 'Tương thích OpenAI';
  @override
  String get anthropic => 'Anthropic';
  @override
  String get temperature => 'Nhiệt độ';
  @override
  String get maxTokens => 'Token tối đa';
  @override
  String get systemPrompt => 'Prompt hệ thống';
  @override
  String get timeout => 'Thời gian chờ (giây)';
  @override
  String get maxRetries => 'Số lần thử lại tối đa';
  @override
  String get testConnection => 'Kiểm tra kết nối';
  @override
  String get connectionSuccess => 'Kết nối thành công';
  @override
  String get aiConnectionFailed => 'Kết nối thất bại';
  @override
  String get enableAiSearch => 'Bật tìm kiếm AI';
  @override
  String get defaultSearchScope => 'Phạm vi tìm kiếm mặc định';
  @override
  String get maxContentReadSize => 'Kích thước đọc nội dung tối đa';
  @override
  String get providerEnabled => 'Nhà cung cấp đã bật';
  @override
  String get providerDisabled => 'Nhà cung cấp đã tắt';
  @override
  String get providerPriority => 'Độ ưu tiên';
  @override
  String get advancedSettings => 'Cài đặt nâng cao';
  @override
  String get testingConnection => 'Đang kiểm tra kết nối...';
  @override
  String get codexOauthDescription =>
      'Dùng phiên đăng nhập Codex/ChatGPT trên máy thay vì khóa API thô.';
  @override
  String get codexCredentialUnavailable =>
      'Không tìm thấy đường dẫn credential Codex trên thiết bị này.';
  @override
  String get codexCredentialMissing =>
      'Không tìm thấy credential Codex OAuth. Hãy chạy codex login trước.';
  @override
  String get launchCodexLogin => 'Mở Codex Login';
  @override
  String get codexLoginLaunched =>
      'Đã mở Codex login trong một cửa sổ terminal riêng.';
  @override
  String get checkCredentials => 'Kiểm tra credential';
  @override
  String deleteProviderConfirmation(String name) =>
      'Bạn có chắc muốn xóa nhà cung cấp "$name"?';
  @override
  String get noProviders => 'Chưa cấu hình nhà cung cấp AI';

  // AI Chat
  @override
  String get aiChat => 'AI Chat';
  @override
  String get askAiToFindFiles => 'Hỏi AI để tìm tệp...';
  @override
  String get sendMessage => 'Gửi';
  @override
  String get clearChat => 'Xóa cuộc trò chuyện';
  @override
  String get searchScope => 'Phạm vi tìm kiếm';
  @override
  String get currentFolder => 'Thư mục hiện tại';
  @override
  String get recursiveSearch => 'Tìm kiếm đệ quy';
  @override
  String get aiTaggedFiles => 'Tệp có nhãn';
  @override
  String get allDrives => 'Tất cả ổ đĩa';
  @override
  String get findingFiles => 'Đang tìm tệp...';
  @override
  String get noResultsFound => 'Không tìm thấy kết quả';
  @override
  String get aiSearchResults => 'Kết quả tìm kiếm AI';
  @override
  String get retryMessage => 'Thử lại';
  @override
  String get providerFallback => 'Đang thử nhà cung cấp tiếp theo...';
  @override
  String get allProvidersFailed => 'Tất cả nhà cung cấp AI đều thất bại';
  @override
  String get setupAiProvider => 'Cài đặt nhà cung cấp AI trong Cài đặt';
  @override
  String get noProviderConfigured => 'Chưa cấu hình nhà cung cấp AI';
  @override
  String get relevanceScore => 'Độ phù hợp';
  @override
  String get aiExplanation => 'Giải thích AI';
  @override
  String get aiSearchMode => 'Tìm kiếm AI';
  @override
  String get switchToAiSearch => 'Chuyển sang tìm kiếm AI';
  @override
  String get switchToNormalSearch => 'Chuyển sang tìm kiếm thường';
  @override
  String get aiChatTab => 'AI Chat';
  @override
  String get suggestRecentPhotos => 'Tìm ảnh gần đây';
  @override
  String get suggestLargeVideos => 'Hiện video lớn';
  @override
  String get suggestTaggedFiles => 'Tệp có nhãn là...';
  @override
  String get fetchModels => 'Lấy danh sách mô hình';
  @override
  String get fetchingModels => 'Đang lấy danh sách mô hình...';
  @override
  String get loadingModels => 'Đang tải mô hình...';
  @override
  String get noModelsFound => 'Không tìm thấy mô hình nào';
  @override
  String get noModelConfigured => 'Chưa có mô hình';
  @override
  String get selectModel => 'Chọn mô hình';
  @override
  String get modelSearchHint => 'Tìm mô hình...';
  @override
  String fetchModelsError(String error) =>
      'Không thể lấy danh sách mô hình: $error';
  @override
  String get newConversation => 'Cuộc trò chuyện mới';
  @override
  String get conversations => 'Cuộc trò chuyện';
  @override
  String get deleteConversation => 'Xóa cuộc trò chuyện';
  @override
  String get noConversations => 'Chưa có cuộc trò chuyện nào';

  // CB Agent rebrand
  @override
  String get cbAgent => 'CB Agent';
  @override
  String get cbAgentTitle => 'CB Agent';
  @override
  String get cbAgentSubtitle => 'Trợ lý AI tích hợp trong CB File Hub';

  // Disk Cleaner (CB Agent skill)
  @override
  String get cbAgentCleanerTitle => 'Dọn rác (CB Agent)';
  @override
  String get diskCleanerNotAvailable => 'Dọn rác chỉ khả dụng trên Windows';
  @override
  String get diskCleanerScanTitle => 'Quét tệp rác';
  @override
  String get diskCleanerScanRunning => 'Đang quét...';
  @override
  String get diskCleanerScanDone => 'Quét xong';
  @override
  String get diskCleanerCleanTitle => 'Dọn tệp rác';
  @override
  String get diskCleanerCleanDone => 'Dọn xong';
  @override
  String get diskCleanerAskAgent => 'Hỏi CB Agent';
  @override
  String get diskCleanerMoveToRecycleBin => 'Chuyển vào Thùng Rác';
  @override
  String get diskCleanerPermanentDelete => 'Xóa vĩnh viễn';
  @override
  String get diskCleanerSelectCategories => 'Chọn danh mục';
  @override
  String get diskCleanerSelectDrives => 'Chọn ổ đĩa';
  @override
  String get diskCleanerScanAgain => 'Quét lại';
  @override
  String get diskCleanerCachedResultStatus =>
      'Đang hiển thị kết quả quét trước (bản lưu đệm). Nhấn Quét lại để làm mới.';

  // Disk Cleaner — extended UI strings
  @override
  String get diskCleanerCancel => 'Hủy';
  @override
  String get diskCleanerShowCleanableOnly => 'Chỉ hiển thị mục có thể dọn';
  @override
  String diskCleanerCleanableOnlyChip(int count) => 'Có thể dọn ($count)';
  @override
  String get diskCleanerCheckAllCleanable => 'Chọn tất cả có thể dọn';
  @override
  String get diskCleanerUncheckAll => 'Bỏ chọn tất cả';

  @override
  String get diskCleanerColumnName => 'Tên';
  @override
  String get diskCleanerColumnSize => 'Kích thước';
  @override
  String get diskCleanerColumnPercentOfParent => '% thư mục cha';
  @override
  String get diskCleanerColumnFiles => 'Tệp';
  @override
  String get diskCleanerBuildingTree => 'Đang xây dựng cây thư mục...';
  @override
  String get diskCleanerNoFilesFound => 'Không tìm thấy tệp nào';
  @override
  String get diskCleanerAnalyzingDisk => 'Đang phân tích dung lượng ổ đĩa...';
  @override
  String get diskCleanerPieChartPending =>
      'Biểu đồ sẽ xuất hiện sau khi quét xong.';
  @override
  String get diskCleanerPieEmpty => 'Trống';
  @override
  String get diskCleanerPreparingFiles => 'Đang chuẩn bị tệp...';
  @override
  String get diskCleanerCleaning => 'Đang dọn dẹp...';
  @override
  String get diskCleanerScanningSelectedDirs =>
      'Đang quét các thư mục đã chọn...';
  @override
  String get diskCleanerDeletingJunkHint =>
      'Đang xóa các mục đã chọn. Nếu tệp bị lỗi, bạn có thể bỏ qua hoặc thử lại.';
  @override
  String get diskCleanerPermanentDeleteLabel => 'Xóa vĩnh viễn';
  @override
  String get diskCleanerRecycleBinLabel => 'Thùng rác';
  @override
  String get diskCleanerDeletingItems => 'Đang xóa các mục...';
  @override
  String get diskCleanerReviewMode => 'Chế độ xem lại';
  @override
  String get diskCleanerBackToResults => 'Quay lại kết quả';
  @override
  String get diskCleanerReviewByAgent => 'Xem lại bằng CB Agent';
  @override
  String get diskCleanerPermanentlyDeleting => 'Đang xóa vĩnh viễn...';
  @override
  String get diskCleanerMovingToRecycleBin => 'Đang chuyển vào Thùng rác...';
  @override
  String get diskCleanerWaitingDecision => 'Đang chờ quyết định của bạn...';
  @override
  String get diskCleanerFileInUse =>
      'Tệp này đang được sử dụng bởi ứng dụng khác.';
  @override
  String get diskCleanerRetryInUseHint =>
      'Thử lại ngay thường sẽ thất bại cho đến khi ứng dụng đang dùng tệp này được đóng.';
  @override
  String get diskCleanerBlockedBy => 'Bị chặn bởi:';
  @override
  String get diskCleanerSkipAllRemaining => 'Bỏ qua tất cả các mục còn lại';
  @override
  String get diskCleanerSkip => 'Bỏ qua';
  @override
  String get diskCleanerTryAgain => 'Thử lại';
  @override
  String get diskCleanerPermanentDeleteConfirmTitle => 'Xóa vĩnh viễn?';
  @override
  String diskCleanerPermanentDeleteFromBinContent(int count, String size) =>
      'Thao tác này sẽ xóa vĩnh viễn $count mục ($size) khỏi Thùng rác. Chúng không thể được khôi phục.';
  @override
  String diskCleanerPermanentDeleteSelectedContent(int count, String size) =>
      'Thao tác này sẽ xóa vĩnh viễn $count mục đã chọn ($size). Chúng không thể được khôi phục.';
  @override
  String get diskCleanerColumnFileName => 'Tên tệp';
  @override
  String get diskCleanerColumnPath => 'Đường dẫn';
  @override
  String get diskCleanerColumnCategory => 'Danh mục';
  @override
  String get diskCleanerRecycleBinEmpty =>
      'Hiện không có mục nào trong Thùng rác.';
  @override
  String diskCleanerItemsInRecycleBin(int count, String size) =>
      '$count mục trong Thùng rác ($size)';
  @override
  String diskCleanerSkippedInUseSnack(int count) =>
      'Đã bỏ qua $count tệp đang được sử dụng. Chi tiết đã được ghi nhật ký.';
  @override
  String diskCleanerSkippedAfterFailureSnack(int count) =>
      'Đã bỏ qua $count tệp do xóa thất bại.';
  @override
  String diskCleanerFreedBadge(String size, int count) =>
      'Đã giải phóng $size  •  $count mục';
  @override
  String diskCleanerFailedBadge(int count) => '$count thất bại';
  @override
  String diskCleanerInUseBadge(int count) => '$count đang dùng';
  @override
  String diskCleanerSkippedBadge(int count) => '$count đã bỏ qua';
  @override
  String diskCleanerSkippedInUseBanner(int count) =>
      'Đã bỏ qua $count tệp đang được sử dụng. Xem nhật ký để biết danh sách đầy đủ.';
  @override
  String diskCleanerSkippedByUserBanner(int count) =>
      'Đã bỏ qua $count tệp do xóa thất bại vì bạn chọn Bỏ qua.';
  @override
  String diskCleanerDeletedPermanentlyBody(int count) =>
      'Đã xóa vĩnh viễn $count mục.';
  @override
  String diskCleanerFreedSpace(String size) => 'Đã giải phóng $size';
  @override
  String diskCleanerPermanentDeleteFinished(int count) =>
      'Đã xóa vĩnh viễn $count mục.';
  @override
  String diskCleanerPermanentDeletingProgress(int done, int total) =>
      'Đang xóa vĩnh viễn... $done / $total';
  @override
  String get diskCleanerDeletingLabel => 'Đang xóa...';
  @override
  String get diskCleanerRemaining => 'còn lại';
  @override
  String diskCleanerDriveFree(String label, String size) =>
      '$label  còn trống $size';
  @override
  String diskCleanerFilesCount(int count) => '$count tệp';
  @override
  String diskCleanerDirsCount(int count) => '$count thư mục';
  @override
  String get diskCleanerStarting => 'Đang bắt đầu...';
  @override
  String diskCleanerDriveSummary(String path, String size, int count) =>
      '$path  $size  •  $count tệp';
  @override
  String get diskCleanerGrowthTitle => 'Thư mục tăng gần đây';
  @override
  String diskCleanerGrowthFilter(int count) => 'Tăng gần đây ($count)';
  @override
  String diskCleanerGrowthIncrease(String size) => '+$size';
  @override
  String diskCleanerGrowthCurrentSize(String size) =>
      'Dung lượng hiện tại: $size';
  @override
  String diskCleanerAgentPath(String path) => 'CB Agent: $path';
  @override
  String diskCleanerItemsBytes(int count, String size) => '$count mục • $size';
  @override
  String diskCleanerSizeFiles(String size, int files) => '$size • $files tệp';

  @override
  String diskCleanerRolledUpItems(int items) => '$items mục nhỏ hơn';
  @override
  String diskCleanerScannedProgress(String size, int files) =>
      'Đã quét $size • $files tệp';
  @override
  String get diskCleanerPieChartPendingScan =>
      'Biểu đồ sẽ xuất hiện ngay khi quét xong';
  @override
  String get diskCleanerIncrementalScanTitle => 'Quét phần thay đổi';
  @override
  String diskCleanerIncrementalScanProgress(int count) =>
      'Đã cập nhật $count thư mục thay đổi';
  @override
  String get diskCleanerFullScanFallback =>
      'Không thể quét phần thay đổi — đã quét lại toàn bộ ổ đĩa';
  @override
  String get diskCleanerOldLargeTitle =>
      'Tệp và thư mục lớn, lâu không hoạt động';
  @override
  String get diskCleanerOldLargeSubtitle =>
      'Chỉ là gợi ý để xem xét. Dấu thời gian hệ thống không khẳng định mục đó không còn được dùng.';
  @override
  String get diskCleanerOldLargeAll => 'Tất cả';
  @override
  String get diskCleanerOldLargeFiles => 'Tệp';
  @override
  String get diskCleanerOldLargeFolders => 'Thư mục';
  @override
  String diskCleanerOldLargeLastActivity(String date) =>
      'Gợi ý hoạt động gần nhất: $date';
  @override
  String get diskCleanerOldLargeReviewOnly => 'Chỉ xem xét';
  @override
  String get diskCleanerOldLargeEmpty =>
      'Không tìm thấy tệp hoặc thư mục lớn nào lâu không hoạt động.';
  @override
  String diskCleanerScanningPath(String path) => 'Đang quét $path';
  @override
  String diskCleanerProcessedCount(int done, int total) =>
      '$done / $total đã xử lý';
  @override
  String diskCleanerJunkSummary(String size) => 'Rác: $size';
  @override
  String get diskCleanerContinue => 'Xem tiếp';
  @override
  String get diskCleanerAiPanelUnavailable =>
      'Bảng AI không khả dụng trong ngữ cảnh này';
  @override
  String get diskCleanerAskAgentAboutThis => 'Hỏi CB Agent về mục này';
  @override
  String get diskCleanerAiDeleteAnalysisIntro =>
      'Hãy phân tích xem tôi có nên xóa tệp hoặc thư mục này không:';
  @override
  String get diskCleanerAiLabelPath => 'Đường dẫn';
  @override
  String get diskCleanerAiLabelType => 'Loại';
  @override
  String get diskCleanerAiLabelName => 'Tên';
  @override
  String get diskCleanerAiLabelSize => 'Dung lượng';
  @override
  String get diskCleanerAiLabelFiles => 'Số tệp';
  @override
  String get diskCleanerAiTypeFile => 'Tệp';
  @override
  String get diskCleanerAiTypeFolder => 'Thư mục';
  @override
  String diskCleanerAiCategoryMarkedJunk(String category) =>
      'Danh mục: $category (được đánh dấu là rác)';
  @override
  String get diskCleanerAiNotMarkedAsJunk =>
      'Mục này không được quy tắc đánh dấu là rác.';
  @override
  String get diskCleanerAiDeleteAnalysisQuestion =>
      'Hãy giải thích mục này có khả năng dùng để làm gì, có an toàn để xóa không, những rủi ro tôi cần cân nhắc, và đưa ra khuyến nghị rõ ràng: xóa, giữ lại, hoặc tự xem xét thêm.';
  @override
  String diskCleanerScanFailedMsg(String error) => 'Quét thất bại: $error';
  @override
  String diskCleanerCleanupFailedMsg(String error) =>
      'Dọn dẹp thất bại: $error';
  @override
  String diskCleanerPermanentDeleteFailedMsg(String error) =>
      'Xóa vĩnh viễn thất bại: $error';
  @override
  String diskCleanerAgentFoundJunk(int count, String size) =>
      'CB Agent tìm thấy $count mục rác ($size)';
  @override
  String diskCleanerAndMoreItems(int count) => '... và $count mục khác';
  @override
  String diskCleanerSelectedBytes(String size, String total) =>
      'Đã chọn: $size / $total';
  @override
  String diskCleanerReviewModeSelected(String size) =>
      'Chế độ xem lại • Đã chọn: $size';
  @override
  String diskCleanerDeletePermanentlyButton(String size) =>
      'Xóa vĩnh viễn $size';
  @override
  String diskCleanerMoveToRecycleBinButton(String size) =>
      'Chuyển $size vào Thùng rác';
  @override
  String diskCleanerReviewAndClean(String size) => 'Xem lại $size & dọn dẹp';
  @override
  String diskCleanerPermanentDeletedSuccess(int count, String size) =>
      'Đã xóa vĩnh viễn $count mục ($size)';
  @override
  String diskCleanerPermanentDeletedWithInUse(
          int count, String size, int skipped) =>
      'Đã xóa vĩnh viễn $count mục ($size). Đã bỏ qua $skipped tệp đang dùng; chi tiết đã được ghi nhật ký.';
  @override
  String diskCleanerPermanentDeletedWithSkipped(
          int count, String size, int skipped) =>
      'Đã xóa vĩnh viễn $count mục ($size). Đã bỏ qua $skipped tệp sau khi xóa thất bại.';

  // Cleaner - chon o dia, don nhanh, ly do rac
  @override
  String get diskCleanerDriveLowSpace => 'Sắp đầy';
  @override
  String diskCleanerDriveCapacity(String used, String total, String free) =>
      'Đã dùng $used trên $total · còn trống $free';
  @override
  String diskCleanerLastScanFound(String when, String junk) =>
      'Quét lần trước $when · tìm thấy $junk rác';
  @override
  String get diskCleanerTimeJustNow => 'vừa xong';
  @override
  String get diskCleanerTimeToday => 'hôm nay';
  @override
  String get diskCleanerTimeYesterday => 'hôm qua';
  @override
  String diskCleanerTimeDaysAgo(int days) => '$days ngày trước';
  @override
  String diskCleanerTimeWeeksAgo(int weeks) => '$weeks tuần trước';
  @override
  String diskCleanerTimeMonthsAgo(int months) => '$months tháng trước';
  @override
  String get diskCleanerQuickCleanHint =>
      'Tệp tạm, bộ nhớ đệm và Thùng rác. Ứng dụng sẽ tự tạo lại khi cần.';
  @override
  String get diskCleanerQuickCleanButton => 'Dọn nhanh';
  @override
  String get diskCleanerQuickCleanScanning => 'Đang tìm mục an toàn...';
  @override
  String get diskCleanerQuickCleanNothing =>
      'Hiện không có mục nào an toàn để dọn';
  @override
  String get diskCleanerQuickCleanReviewTitle => 'Xem lại trước khi dọn nhanh';
  @override
  String diskCleanerQuickCleanReviewSubtitle(int count, String size) =>
      '$count mục trong các nhóm này, tổng cộng $size.';
  @override
  String get diskCleanerQuickCleanRecycleNote =>
      'Tất cả sẽ được chuyển vào Thùng rác, bạn có thể khôi phục từ đó.';
  @override
  String get diskCleanerCategoryWindowsTemp => 'Tệp tạm của Windows';
  @override
  String get diskCleanerCategoryBrowserCache => 'Bộ nhớ đệm trình duyệt';
  @override
  String get diskCleanerCategoryRecycleBin => 'Thùng rác';
  @override
  String get diskCleanerCategoryThumbnailCache => 'Bộ nhớ đệm ảnh thu nhỏ';
  @override
  String get diskCleanerCategoryAppCache => 'Bộ nhớ đệm ứng dụng';
  @override
  String get diskCleanerCategoryCrashLogs => 'Tệp sự cố và nhật ký';
  @override
  String get diskCleanerCategoryWindowsUpdate => 'Bộ nhớ đệm Windows Update';
  @override
  String get diskCleanerCategoryPrefetch => 'Dữ liệu Prefetch';
  @override
  String get diskCleanerCategoryDeliveryOptimization =>
      'Tệp Delivery Optimization';
  @override
  String get diskCleanerCategoryDevCache => 'Bộ nhớ đệm lập trình';
  @override
  String get diskCleanerReasonWindowsTemp =>
      'Do ứng dụng để lại. Xóa an toàn, không có gì phụ thuộc vào chúng.';
  @override
  String get diskCleanerReasonBrowserCache =>
      'Trình duyệt sẽ tự tạo lại. Lần đầu mở trang có thể chậm hơn một chút.';
  @override
  String get diskCleanerReasonRecycleBin =>
      'Các tệp đã xóa đang chờ được dọn sạch.';
  @override
  String get diskCleanerReasonThumbnailCache =>
      'Windows sẽ tạo lại ảnh thu nhỏ khi bạn mở thư mục lần sau.';
  @override
  String get diskCleanerReasonAppCache =>
      'Dữ liệu tạm của ứng dụng. Ứng dụng sẽ tạo lại và bạn vẫn giữ đăng nhập.';
  @override
  String get diskCleanerReasonCrashLogs =>
      'Tệp chẩn đoán từ các lần treo trước, chỉ hữu ích khi cần gỡ lỗi.';
  @override
  String get diskCleanerReasonWindowsUpdate =>
      'Bộ cài của các bản cập nhật đã được áp dụng xong.';
  @override
  String get diskCleanerReasonPrefetch =>
      'Dữ liệu tăng tốc khởi động. Windows sẽ dựng lại sau vài lần mở ứng dụng.';
  @override
  String get diskCleanerReasonDeliveryOptimization =>
      'Tệp cập nhật lưu sẵn để chia sẻ với máy khác trong mạng của bạn.';
  @override
  String get diskCleanerReasonDevCache =>
      'Bộ nhớ đệm build và gói. Công cụ của bạn sẽ tải lại hoặc dựng lại.';
  @override
  String get diskCleanerReasonGeneric =>
      'Khớp với vị trí rác đã biết và có thể xóa an toàn.';

  // Cleaner - bo loc nhanh cho cay thu muc
  @override
  String get diskCleanerPresetTooltip => 'Lọc cây thư mục';
  @override
  String get diskCleanerPresetAll => 'Tất cả';
  @override
  String get diskCleanerPresetLargeFiles => 'Tệp trên 1 GB';
  @override
  String get diskCleanerPresetLogsCaches => 'Nhật ký và bộ nhớ đệm';
  @override
  String get diskCleanerPresetInstallers => 'Bộ cài và tệp nén';

  // Cleaner - ket qua sau khi don
  @override
  String diskCleanerFreeSpaceBeforeAfter(String before, String after) =>
      'Dung lượng trống: $before → $after';
  @override
  String get diskCleanerGrowthWatchTitle => 'Đang tăng kể từ lần quét trước';
  @override
  String diskCleanerGrowthWatchLine(String path, String size) =>
      '$path  +$size';

  // Cleaner App Insights
  @override
  String get cleanerUtilitiesTitle => 'CB Agent Cleaner';
  @override
  String get cleanerUtilitiesSubtitle =>
      'Các tiện ích giúp máy tính gọn gàng và hoạt động tốt hơn';
  @override
  String get cleanerUtilitiesStorageGroup => 'Dung lượng';
  @override
  String get cleanerDiskUsageTitle => 'Dung lượng ổ đĩa';
  @override
  String get cleanerDiskUtilityDescription =>
      'Xem thư mục lớn và dọn rác đã được xác nhận an toàn';
  @override
  String get cleanerAppsTitle => 'Ứng dụng';
  @override
  String get cleanerAppsUtilityDescription =>
      'Tìm ứng dụng lớn, ít dùng và xem dữ liệu liên quan';
  @override
  String get cleanerAppsLoading => 'Đang phân tích ứng dụng đã cài...';
  @override
  String get cleanerAppsUnavailable =>
      'Thông tin ứng dụng sẽ có sau khi quét ổ đĩa hoàn tất.';
  @override
  String cleanerAppsLoadFailed(String error) =>
      'Không thể phân tích ứng dụng đã cài: $error';
  @override
  String get cleanerAppsPartialBanner => 'Dữ liệu vẫn đang được cập nhật.';
  @override
  String get cleanerAppsSearchHint => 'Tìm ứng dụng';
  @override
  String get cleanerAppsFilterAll => 'Tất cả';
  @override
  String get cleanerAppsFilterAttention => 'Nên xem';
  @override
  String get cleanerAppsFilterLarge => 'Nặng';
  @override
  String get cleanerAppsFilterStale => 'Ít mở';
  @override
  String get cleanerAppsFilterCleanable => 'Dọn được';
  @override
  String get cleanerAppsSortLabel => 'Sắp xếp';
  @override
  String get cleanerAppsSortSize => 'Lớn nhất trước';
  @override
  String get cleanerAppsSortName => 'Tên';
  @override
  String get cleanerAppsSortLastOpened => 'Hoạt động cũ nhất';
  @override
  String get cleanerAppsLargeThresholdLabel => 'Ứng dụng lớn';
  @override
  String get cleanerAppsStaleThresholdLabel => 'Lâu chưa thấy';
  @override
  String cleanerAppsDays(int days) => '$days ngày';
  @override
  String get cleanerAppsSummaryFootprint => 'Dung lượng đã xác nhận';
  @override
  String get cleanerAppsSummaryAttention => 'Nên xem lại';
  @override
  String get cleanerAppsSummaryLarge => 'Ứng dụng lớn';
  @override
  String get cleanerAppsSummaryStale => 'Lâu chưa thấy mở';
  @override
  String get cleanerAppsSummaryCleanable => 'Cache có thể dọn';
  @override
  String cleanerAppsThresholdAtLeast(String size) => 'Từ $size trở lên';
  @override
  String cleanerAppsNotSeenForDays(int days) =>
      'Không ghi nhận lần mở trong $days ngày';
  @override
  String get cleanerAppsReviewableCache => 'Có thể xem lại an toàn';
  @override
  String cleanerAppsShowingCount(int count) => 'Đang hiển thị $count ứng dụng';
  @override
  String get cleanerAppsNoResults => 'Không có ứng dụng phù hợp bộ lọc.';
  @override
  String get cleanerAppsUnknown => 'Không rõ';
  @override
  String cleanerAppsLastOpened(String date) => 'Thấy mở gần nhất: $date';
  @override
  String cleanerAppsNotOpenedForDays(int days) => '$days ngày chưa mở';
  @override
  String get cleanerAppsUsageUnknownCompact => 'Chưa có dữ liệu mở';
  @override
  String get cleanerAppsAttentionBadge => 'Nên xem';
  @override
  String get cleanerAppsViewOptions => 'Tùy chọn hiển thị';
  @override
  String cleanerAppsUsageEvidence(String source, String confidence) =>
      '$source • $confidence';
  @override
  String cleanerAppsPossibleSize(String size) => 'Có thể thuộc app: $size';
  @override
  String cleanerAppsCleanableAmount(String size) => 'Có thể dọn: $size';
  @override
  String get cleanerAppsDetails => 'Chi tiết ứng dụng';
  @override
  String get cleanerAppsUsageEvidenceLabel => 'Bằng chứng sử dụng';
  @override
  String get cleanerAppsSelectApp =>
      'Chọn một ứng dụng để xem dung lượng lưu trữ.';
  @override
  String get cleanerAppsConfirmedFootprint => 'Đã xác nhận';
  @override
  String get cleanerAppsPossibleFootprint => 'Có thể thuộc app';
  @override
  String get cleanerAppsStorageBreakdown => 'Phân bổ dung lượng';
  @override
  String get cleanerAppsNoStorageDetails =>
      'Chưa có vị trí lưu trữ đo được cho ứng dụng này.';
  @override
  String get cleanerAppsSharedFolders =>
      'Thư mục lớn dùng chung / chưa xác định';
  @override
  String get cleanerAppsSharedFoldersDescription =>
      'Các thư mục này không được gán cho riêng một ứng dụng và không bao giờ được chọn để dọn.';
  @override
  String get cleanerAppsOpenFolder => 'Mở thư mục';
  @override
  String get cleanerAppsManageInWindows => 'Quản lý trong Windows';
  @override
  String get cleanerAppsReviewCleanable => 'Xem dữ liệu có thể dọn';
  @override
  String get cleanerAppsAskAgent => 'Hỏi CB Agent';
  @override
  String cleanerAppsVersion(String version) => 'Phiên bản $version';
  @override
  String cleanerAppsInstalledOrUpdated(String date) =>
      'Đã cài hoặc cập nhật: $date';
  @override
  String get cleanerAppsSourceWin32 => 'Ứng dụng Win32';
  @override
  String get cleanerAppsSourceStore => 'Ứng dụng Microsoft Store';
  @override
  String get cleanerAppsMeasurementMeasured => 'Đã đo';
  @override
  String get cleanerAppsMeasurementEstimated => 'Windows ước tính';
  @override
  String get cleanerAppsMeasurementPartial => 'Một phần';
  @override
  String get cleanerAppsMeasurementUnknown => 'Không rõ dung lượng';
  @override
  String get cleanerAppsAttributionConfirmed => 'Đã xác nhận';
  @override
  String get cleanerAppsAttributionPossible => 'Có thể thuộc app';
  @override
  String get cleanerAppsAttributionShared => 'Dùng chung';
  @override
  String get cleanerAppsUsageUserAssist => 'Lịch sử mở của Windows';
  @override
  String get cleanerAppsUsagePrefetch => 'Windows Prefetch';
  @override
  String get cleanerAppsConfidenceHigh => 'Độ tin cậy cao';
  @override
  String get cleanerAppsConfidenceMedium => 'Độ tin cậy trung bình';
  @override
  String get cleanerAppsStorageInstall => 'Thư mục cài đặt';
  @override
  String get cleanerAppsStorageLocalData => 'Dữ liệu ứng dụng cục bộ';
  @override
  String get cleanerAppsStorageRoamingData => 'Dữ liệu ứng dụng roaming';
  @override
  String get cleanerAppsStoragePackageData => 'Dữ liệu gói ứng dụng';
  @override
  String get cleanerAppsStorageProgramData => 'Dữ liệu chương trình dùng chung';
  @override
  String get cleanerAppsStorageCache => 'Bộ nhớ đệm';
  @override
  String get cleanerAppsStorageLogs => 'Nhật ký';
  @override
  String get cleanerAppsStorageShared => 'Dung lượng dùng chung';
  @override
  String get cleanerAppsStorageUnknown => 'Dung lượng khác';
  @override
  String get cleanerAppsCleanableBadge => 'Có thể dọn';

  @override
  String get aiThinking0 => 'Đang suy nghĩ...';
  @override
  String get aiThinking1 => 'Đang phân tích...';
  @override
  String get aiThinking2 => 'Đang tìm kiếm...';
  @override
  String get aiThinking3 => 'Đang tạo phản hồi...';
  @override
  String get aiWaitingApproval => 'Đang chờ bạn phê duyệt...';
  @override
  String aiRunningTool(String toolName) => 'Đang chạy $toolName...';

  // Local AI Advisor
  @override
  String get localAiAdvisor => 'Trợ lý AI nội bộ';
  @override
  String get localAiAdvisorDescription =>
      'Gợi ý dọn dẹp trên thiết bị với mô hình Gemma 4 của bạn';
  @override
  String get huggingFaceToken => 'Token Hugging Face';
  @override
  String get huggingFaceTokenHint =>
      'Tùy chọn: Cho mô hình riêng tư hoặc truy cập catalog mở rộng';
  @override
  String get pasteToken => 'Dán Token';
  @override
  String get tokenSaved => 'Token đã lưu an toàn';
  @override
  String get clearToken => 'Xóa Token';
  @override
  String get browseModels => 'Duyệt mô hình';
  @override
  String get installedModels => 'Mô hình đã cài đặt';
  @override
  String get noModelsInstalled => 'Chưa cài đặt mô hình nào';
  @override
  String get installModel => 'Cài đặt';
  @override
  String get uninstallModel => 'Gỡ cài đặt';
  @override
  String get selectActiveModel => 'Đặt làm mặc định';
  @override
  String get modelInstalling => 'Đang cài đặt mô hình...';
  @override
  String get modelInstalled => 'Đã cài đặt mô hình thành công';
  @override
  String get modelUninstalled => 'Đã gỡ cài đặt mô hình';
  @override
  String get downloadProgress => 'Tiến trình tải xuống';
  @override
  String get noTokenSet => 'Chưa đặt token';
  @override
  String get setTokenFirst => 'Đặt token Hugging Face trước';
  @override
  String get openLocation => 'Mở vị trí';
  @override
  String get localAiIncompatibleArtifact =>
      'Tệp mô hình này không tương thích với trò chuyện trên thiết bị. Cài đặt lại phiên bản LiteRT-LM để bật trò chuyện cục bộ.';
  @override
  String get localAiReinstallCompatible => 'Cài đặt lại mô hình tương thích';
  @override
  String get localAiContextWindow => 'Cửa sổ ngữ cảnh';
  @override
  String get localAiContextWindowHint =>
      'Số token tối đa mỗi lượt trò chuyện (câu hỏi + trả lời). Giá trị cao xử lý được tệp lớn và hội thoại dài hơn nhưng tốn nhiều bộ nhớ hơn.';
  @override
  String get localAiTokensSuffix => 'token';
  @override
  String get localAiInvalidTokenCount => 'Vui lòng nhập số hợp lệ';
}
