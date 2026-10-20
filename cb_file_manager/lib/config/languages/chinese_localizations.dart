import 'app_localizations.dart';

class ChineseLocalizations implements AppLocalizations {
  @override
  String get torrentOpeningOptions => '打开种子时';
  @override
  String get torrentShowDownloadDialog => '打开种子时显示下载选项';
  @override
  String get torrentShowDownloadDialogHint =>
      '关闭后使用已保存的下载文件夹和立即开始偏好。若尚未保存文件夹，仍会提示选择。';
  @override
  String get torrentImportMenu => '导入';
  @override
  String torrentImportFrom(String app) => '从 $app 导入';
  @override
  String get torrentClientImportHint =>
      '从检测到的配置文件或其他文件夹导入已保存的 .torrent 文件。将应用所选的存储模式，已下载的内容会保留。';
  @override
  String get torrentClientNotFound => '未找到配置文件。请选择此应用存放 .torrent 文件的文件夹。';
  @override
  String get torrentClientSourceRequired => '请选择包含 .torrent 文件的现有文件夹。';
  @override
  String get torrentAddLink => '通过链接添加种子';
  @override
  String get torrentLinkHint => '粘贴 HTTP/HTTPS 种子网址或磁力链接。';
  @override
  String get torrentRefreshImport => '导入新种子 (F5)';
  @override
  String get torrentStartImmediately => '立即开始下载';
  @override
  String get torrentDestinationRequired => '请选择或输入下载文件夹的完整路径。';
  @override
  String get torrentDestinationLocked => '更改下载文件夹前，请先停止此任务。';
  @override
  String torrentColumn(String column) =>
      const {
        'status': '下载状态',
        'progress': '进度',
        'downSpeed': '下载速度',
        'upSpeed': '上传速度',
        'seeds': '做种',
        'peers': '用户',
        'eta': '剩余时间',
        'downloaded': '已下载',
        'uploaded': '已上传',
        'ratio': '分享率',
        'files': '文件',
        'group': '分组',
        'destination': '下载文件夹',
        'hash': '信息哈希',
        'remaining': '剩余',
        'tracker': 'Tracker',
        'trackerCount': 'Tracker 数',
        'torrentCreated': '种子创建时间',
        'createdBy': '创建者',
        'comment': '备注',
        'private': '隐私',
        'privateYes': '私有',
        'privateNo': '公开',
        'pieceSize': '分块大小',
        'pieceCount': '分块数',
        'metainfoSize': '种子文件大小',
        'torrentFile': '种子文件',
        'source': '来源',
        'error': '错误',
        'taskId': '任务 ID',
        'filters': '筛选种子',
        'seedsHint': '当前连接到此下载的做种者数量。',
        'peersHint': '已连接用户总数，包括做种者和 Web 种子。',
      }[column] ??
      column;
  @override
  String get torrentStatusLabel => '状态';
  @override
  String get torrents => '种子';
  @override
  String get torrentDuplicateTitle => '种子已存在';
  @override
  String get torrentDuplicateHint => '要将 Tracker 和来源合并到此种子吗？下载状态、目标位置和现有文件将保留。';
  @override
  String get torrentMerge => '合并';
  @override
  String get torrentReveal => '在列表中显示';
  @override
  String torrentSaved(String name) => '已保存：$name';
  @override
  String get torrentCopyMagnet => '复制磁力链接';
  @override
  String get torrentAddMagnet => '添加磁力链接';
  @override
  String get torrentDefaultApps => '选择 Windows 默认应用';
  @override
  String get torrentDefaultAppsHint =>
      '在 Windows 默认应用中，将 CB File Hub 设为 .torrent 文件和 MAGNET 链接的默认应用。';
  @override
  String get torrentOrganize => '整理种子文件';
  @override
  String torrentStorageMode(String mode) =>
      const {
        'index': '仅建立索引，保留原文件',
        'copy': '复制到所选存储文件夹',
        'move': '移动到所选存储文件夹',
      }[mode] ??
      mode;
  @override
  String get torrentSubtitle => '无论文件在哪里，都集中在一个库中。';
  @override
  String get torrentStorage => '种子存储文件夹';
  @override
  String get torrentStorageHint =>
      '“复制”会按哈希整理已建立索引的种子文件。“移动”会在验证已存储的副本后，先显示确认提示，再清理现有的原文件。之后的导入将使用所选模式。下载目标位置需单独选择。';
  @override
  String get torrentMoveConfirmTitle => '移动种子并清理来源？';
  @override
  String torrentMoveConfirmHint(int count) =>
      '下方列出了 $count 个来源 .torrent 文件。只有在验证已存储的副本后，才会删除对应的原文件。已下载的内容和其他来源文件会保留。之后的导入将使用“移动”模式。';
  @override
  String get torrentMoveConfirm => '确认移动并清理';
  @override
  String get torrentImport => '导入 .torrent';
  @override
  String get qbittorrentImport => '从 qBittorrent 导入';
  @override
  String get qbittorrentImportHint =>
      '自动查找 Windows 的 BT_backup 文件夹，或选择便携版配置文件。种子元数据和 .fastresume 备份会保存到您选择的文件夹。缺少 .torrent 的条目将作为磁力链接导入；选择下载时才会获取元数据。';
  @override
  String get qbittorrentChooseSource => '选择 BT_backup';
  @override
  String get qbittorrentRemoveSources => '导入后从 qBittorrent 中移除种子';
  @override
  String get qbittorrentRemoveHint =>
      '直接清理匹配的 .torrent 和 .fastresume 文件。请先关闭 qBittorrent；已下载的内容会保留。';
  @override
  String get qbittorrentConfirmTitle => '从 qBittorrent 中移除这些种子？';
  @override
  String qbittorrentConfirmHint(int count) =>
      '在种子或磁力链接及续传备份已存入 CB File Hub 并通过验证后，仅清理下方的 $count 个来源文件。已下载的内容和其他文件会保留。qBittorrent 必须处于关闭状态。';
  @override
  String get qbittorrentConfirm => '确认导入并清理';
  @override
  String qbittorrentFound(int torrents, int files) =>
      '找到 $torrents 个种子 · $files 个来源文件';
  @override
  String qbittorrentProgress(int completed, int total) =>
      '正在导入 $completed / $total 个种子';
  @override
  String qbittorrentResult(int stored, int cleaned, int failed) =>
      '已存储：$stored · 已清理来源：$cleaned · 失败：$failed';
  @override
  String qbittorrentProblem(String problem) =>
      const {
        'running': '请完全关闭 qBittorrent 后重试。若要在 qBittorrent 运行时复制，请取消勾选清理来源。',
        'sqlite':
            '此配置文件包含 torrents.db。清理 BT_backup 无法移除 SQLite 条目，因此已保留来源。请选择 Fastresume 配置文件。',
        'changed': '预览后来源已发生变化。已保留来源，请重新加载列表。',
        'destination': '请将种子存储位置选在来源 BT_backup 文件夹之外。',
        'missingMetainfo':
            '未找到 .torrent 文件或有效的已索引元数据。已保留 qBittorrent 的 .fastresume。',
        'noSources': '未找到 BT_backup 文件夹。请选择 qBittorrent 数据文件夹。',
      }[problem] ??
      problem;
  @override
  String get torrentScanFolder => '扫描文件夹';
  @override
  String get torrentScanSystem => '扫描所有本地驱动器';
  @override
  String get torrentAutoImport => '每 5 分钟自动导入来源文件夹';
  @override
  String get torrentSources => '导入来源';
  @override
  String get torrentEngine => '选择 aria2c 可执行文件';
  @override
  String get torrentDownload => '下载到…';
  @override
  String get torrentPause => '暂停';
  @override
  String get torrentResume => '继续';
  @override
  String get torrentStop => '停止下载';
  @override
  String get torrentGroup => '分组';
  @override
  String get torrentRemove => '从索引中移除';
  @override
  String get torrentRemoveHint =>
      '下载将会停止。种子元数据、原文件和已下载的文件仍会保留在磁盘上。之后再次扫描时可重新导入。';
  @override
  String get torrentEmpty => '未找到种子。请导入文件或扫描文件夹以开始。';
  @override
  String get torrentScanHint =>
      '扫描所有已挂载本地驱动器上的 .torrent 文件，包括种子客户端的备份。文件按内容分组并去重。不会导入客户端现有的下载位置和会话。';
  @override
  String get torrentScanLog => '打开扫描错误日志';
  @override
  String get torrentNoStorage => '导入前，请先选择种子元数据的存储位置。';
  @override
  String get torrentOpenFolder => '打开下载文件夹';
  @override
  String get torrentDesktopOnly => '种子下载需要桌面版 aria2。可在可访问的本地文件夹上建立索引。';
  @override
  String torrentStatus(String status) =>
      const {
        'library': '库',
        'active': '下载中',
        'waiting': '排队中',
        'paused': '已暂停',
        'complete': '已完成',
        'error': '失败',
      }[status] ??
      status;
  @override
  String torrentCategory(String category) =>
      const {
        'video': '视频',
        'audio': '音频',
        'documents': '文档',
        'other': '其他',
      }[category] ??
      category;
  @override
  String torrentScanSummary(
    int visited,
    int imported,
    int duplicates,
    int failed,
  ) => '已检查 $visited 个种子 · 已导入 $imported 个 · 重复 $duplicates 个 · 错误 $failed 个';
  @override
  String get torrentFilesPerPage => '每页文件数';
  @override
  String torrentPageSummary(int first, int last, int total) =>
      '第 $first–$last 个，共 $total 个种子';
  @override
  String get galleryNsfwLabel => 'NSFW 内容';
  @override
  String get galleryNsfwDescription => '不在主页上显示此合集的图片和视频预览。';

  @override
  String get homeSubtitle => '您的文件夹、照片和视频，触手可及。';
  @override
  String get homeRecentFolders => '从上次离开的地方继续';
  @override
  String get homeRecentEmpty => '您访问过的文件夹会显示在这里。打开一个文件夹即可开始。';
  @override
  String get homeRecentUnavailable => '无法加载最近的文件夹。';
  @override
  String get homePhotosSubtitle => '从您的照片收藏中获取一点灵感。';
  @override
  String get homeVideosSubtitle => '您的视频收藏，随时可以探索。';
  @override
  String get homePinnedEmpty => '在文件浏览器中固定常用文件夹，以便快速访问。';

  @override
  String get sshDisplayName => '名称';
  @override
  String get sshRequired => '此字段为必填项。';
  @override
  String get sshInvalidHost => '请输入主机名或 IP 地址，不要包含网址或路径。';
  @override
  String get sshInvalidPort => '请输入 1 到 65535 之间的端口。';

  @override
  String get sshWorkspace => 'SSH 工作区';
  @override
  String get sshHosts => '主机';
  @override
  String get sshKeys => 'SSH 密钥';
  @override
  String get sshKnownHosts => '受信任的主机';
  @override
  String get sshAddHost => '添加主机';
  @override
  String get sshEditHost => '编辑主机';
  @override
  String get sshGenerateKey => '生成 Ed25519 密钥';
  @override
  String get sshImportKey => '导入私钥';
  @override
  String get sshOpenTerminal => '打开终端';
  @override
  String get sshBrowseFiles => '浏览 SFTP';
  @override
  String get sshGroup => '分组';
  @override
  String get sshAuthMethod => '身份验证';
  @override
  String get sshPasswordAuth => '密码';
  @override
  String get sshKeyAuth => 'SSH 密钥';
  @override
  String get sshNoHosts => '添加 SSH 主机后，即可打开终端或浏览其文件。';
  @override
  String get sshNoKeys => '导入私钥或生成 Ed25519 密钥。';
  @override
  String get sshNoTrustedHosts => '您批准连接后，主机指纹会显示在这里。';
  @override
  String get sshPrivateKey => '私钥 (OpenSSH / PEM)';
  @override
  String get sshPassphrase => '密钥密码';
  @override
  String get sshCopyPublicKey => '复制公钥';
  @override
  String get sshTrustHost => '信任此 SSH 主机？';
  @override
  String get sshHostKeyChanged => 'SSH 主机密钥已更改';
  @override
  String get sshVerifyFingerprint => '信任之前，请向服务器管理员核实此指纹。';
  @override
  String get sshTrustAndConnect => '信任并连接';
  @override
  String get sshForgetHost => '移除受信任的主机';
  @override
  String get sshDeleteConfirm => '移除此已保存的项目？';
  @override
  String get sshKeyInUse => '删除此密钥前，请先更改使用该密钥的主机的身份验证方式。';
  @override
  String get sshConnecting => '正在连接…';
  @override
  String get sshDisconnected => '会话已断开';
  @override
  String get sshReconnect => '重新连接';
  @override
  String get sshClearTerminal => '清除终端';
  @override
  String get sshVaultHint => '密码和私钥保存在此设备的安全存储中。';
  @override
  String get ftpSecurity => '连接安全';
  @override
  String get ftpPlain => 'FTP（未加密）';
  @override
  String get ftpExplicitTls => 'FTPS — 显式 TLS (21)';
  @override
  String get ftpImplicitTls => 'FTPS — 隐式 TLS (990)';

  @override
  String get appTitle => 'CB File Hub';

  // Common actions
  @override
  String get ok => '确定';
  @override
  String get cancel => '取消';
  @override
  String get save => '保存';
  @override
  String get delete => '删除';
  @override
  String get edit => '编辑';
  @override
  String get close => '关闭';
  @override
  String get exit => '退出';
  @override
  String get search => '搜索';
  @override
  String get all => '全部';
  @override
  String get settings => '设置';

  @override
  String get moreOptions => '更多选项';
  @override
  String get thirdPartyApps => '第三方应用';
  @override
  String get configureContextMenu => '配置右键菜单';
  @override
  String get contextMenuLayout => '右键菜单布局';
  @override
  String get contextMenuLayoutDescription => '重新排序或隐藏右键单击时显示的命令';
  @override
  String get contextMenuLayoutHint => '拖动命令即可重新排序。隐藏的命令仍可在此处找到。';
  @override
  String get contextMenuForFiles => '文件';
  @override
  String get contextMenuForFolders => '文件夹';
  @override
  String get contextMenuForMultipleItems => '多个项目';
  @override
  String get resetContextMenuLayout => '重置布局';
  @override
  String get contextMenuLayoutReset => '右键菜单布局已重置';

  // File operations
  @override
  String get copy => '复制';
  @override
  String get cut => '剪切';
  @override
  String get move => '移动';
  @override
  String get rename => '重命名';
  @override
  String get newFolder => '新建文件夹';
  @override
  String get properties => '属性';
  @override
  String get openWith => '打开方式';
  @override
  String get chooseDefaultApp => '选择默认应用';

  @override
  String get useSelectedAppAsVideoDefault => '在 CB File Hub 中默认使用所选应用播放视频';
  @override
  String get applicationsLoadError => '无法加载应用程序。';
  @override
  String get noApplicationsFound => '未找到可打开此文件类型的应用程序。';
  @override
  String get setCoolBirdAsDefaultForVideos => '将 CB File Hub 设为视频文件的默认应用';
  @override
  String get setCoolBirdAsDefaultForVideosAndroidHint =>
      '正在打开“设置”。请在“默认打开”中，为视频文件启用 CB File Hub。';
  @override
  String get setCoolBirdAsDefaultForArchives => '将 CB File Hub 设为压缩文件的默认应用';
  @override
  String get setCoolBirdAsDefaultForArchivesSuccess =>
      'CB File Hub 现已成为压缩文件的默认应用。';
  @override
  String get setCoolBirdAsDefaultForArchivesFailed =>
      '无法将 CB File Hub 设为压缩文件的默认应用。';
  @override
  String get openFolder => '打开文件夹';
  @override
  String get openFile => '打开文件';
  @override
  String get viewImage => '查看图片';
  @override
  String get open => '打开';
  @override
  String get pasteHere => '粘贴到此处';
  @override
  String get manage => '管理';

  @override
  String get manageTags => '管理标签';
  @override
  String get moveToTrash => '移到回收站';

  @override
  String get errorAccessingDirectory => '访问目录时出错';
  @override
  String errorAccessingDirectoryWithError(String error) => '访问目录时出错：$error';
  @override
  String accessDeniedAdminMessage(String path) => '访问被拒绝：访问 $path 需要管理员权限';
  @override
  String directoryDoesNotExist(String path) => '目录不存在：$path';

  // Action bar tooltips
  @override
  String get searchTooltip => '搜索';

  @override
  String get sortByTooltip => '排序方式';

  @override
  String get refreshTooltip => '刷新';

  @override
  String get moreOptionsTooltip => '更多选项';

  @override
  String get adjustGridSizeTooltip => '调整项目大小';

  @override
  String get columnSettingsTooltip => '列设置';

  @override
  String get viewModeTooltip => '视图模式';

  // Dialog titles
  @override
  String get adjustGridSizeTitle => '调整项目大小';

  @override
  String get columnVisibilityTitle => '自定义列显示';

  // Button labels
  @override
  String get apply => '应用';

  // Sort options
  @override
  String get sortNameAsc => '名称 (A → Z)';

  @override
  String get sortNameDesc => '名称 (Z → A)';

  @override
  String get sortDateModifiedOldest => '修改日期（最早优先）';

  @override
  String get sortDateModifiedNewest => '修改日期（最新优先）';

  @override
  String get sortDateCreatedOldest => '创建日期（最早优先）';

  @override
  String get sortDateCreatedNewest => '创建日期（最新优先）';

  @override
  String get sortSizeSmallest => '大小（最小优先）';

  @override
  String get sortSizeLargest => '大小（最大优先）';

  @override
  String get sortTypeAsc => '文件类型 (A → Z)';

  @override
  String get sortTypeDesc => '文件类型 (Z → A)';

  @override
  String get sortExtensionAsc => '扩展名 (A → Z)';

  @override
  String get sortExtensionDesc => '扩展名 (Z → A)';

  @override
  String get sortAttributesAsc => '属性 (A → Z)';

  @override
  String get sortAttributesDesc => '属性 (Z → A)';

  // View modes
  @override
  String get viewModeList => '列表';

  @override
  String get viewModeGrid => '网格';

  @override
  String get viewModeDetails => '详细信息';

  @override
  String get viewModeGridPreview => '网格 + 预览';

  @override
  String get viewModeColumns => '分栏';

  @override
  String get viewModeTree => '树状';

  @override
  String get viewModeTiles => '平铺';

  @override
  String get defaultViewMode => '默认视图模式';

  @override
  String get defaultViewModeDescription => '用于没有单独保存视图模式的文件夹';

  @override
  String get propertiesAndTags => '属性和标签';
  @override
  String get showPropertiesPane => '显示属性和标签';
  @override
  String get hidePropertiesPane => '折叠属性和标签';
  @override
  String get propertiesSelectFile => '选择文件以查看其属性和标签。';
  @override
  String get propertiesFilesOnly => '标签仅适用于所选文件。';
  @override
  String get propertiesTagFailure => '部分文件无法更新';
  @override
  String get propertiesResize => '调整属性面板大小';
  @override
  String get propertiesTagHint => '标签名称或 父标签:子标签';

  @override
  String get previewPaneTitle => '预览';

  @override
  String get dragFilePane => '拖动以停靠在另一个窗格旁';

  @override
  String get resetFilePaneLayout => '恢复默认窗格布局';

  @override
  String get previewSelectFile => '选择文件以预览';

  @override
  String get previewNotSupported => '此文件类型不支持预览';

  @override
  String get archiveSectionTitle => '压缩文件';

  @override
  String get archiveBrowseTitle => '浏览内容';

  @override
  String get archiveExtractHere => '解压到此处';

  @override
  String get archiveExtractTo => '解压到…';

  @override
  String get archiveExtractToTitle => '选择解压文件夹';

  @override
  String get archiveExtractAll => '全部解压';

  @override
  String get archiveExtracting => '正在解压…';

  @override
  String get archiveExtractComplete => '解压完成';

  @override
  String archiveExtractFailed(String error) => '解压失败：$error';

  @override
  String get archiveEmpty => '此压缩文件为空';

  @override
  String archivePreviewSummary(int count) => '$count 个项目';

  @override
  String archivePreviewMore(int count) => '… 以及另外 $count 个';

  @override
  String get previewUnavailable => '无法预览';

  @override
  String get previewTextTruncated => '正在显示部分内容';

  @override
  String get previewTextTooLarge => '文件太大，无法预览';

  @override
  String get showPreview => '显示预览';

  @override
  String get hidePreview => '隐藏预览';

  // Column names
  @override
  String get columnName => '名称';

  @override
  String get columnSize => '大小';

  @override
  String get columnType => '类型';

  @override
  String get columnDateModified => '修改日期';

  @override
  String get columnDateCreated => '创建日期';

  @override
  String get columnAttributes => '属性';

  @override
  String get columnDateAccessed => '访问日期';

  @override
  String get columnExtension => '扩展名';

  @override
  String get columnPath => '路径';

  @override
  String get columnTags => '标签';

  @override
  String get columnDimensions => '尺寸';

  @override
  String get columnDuration => '时长';

  @override
  String get columnItemCount => '项目数';

  // Column descriptions
  @override
  String get columnSizeDescription => '显示文件大小';

  @override
  String get columnTypeDescription => '显示文件类型（PDF、Word 等）';

  @override
  String get columnDateModifiedDescription => '显示文件的修改日期和时间';

  @override
  String get columnDateCreatedDescription => '显示文件的创建日期和时间';

  @override
  String get columnAttributesDescription => '显示文件属性（读写权限）';

  @override
  String get columnDateAccessedDescription => '显示文件最后一次访问的日期和时间';

  @override
  String get columnExtensionDescription => '显示文件扩展名（如 .mp4、.docx）';

  @override
  String get columnPathDescription => '显示文件的相对路径';

  @override
  String get columnTagsDescription => '显示文件标签';

  @override
  String get columnDimensionsDescription => '显示图片/视频尺寸（宽 x 高）';

  @override
  String get columnDurationDescription => '显示视频/音频文件的媒体时长';

  @override
  String get columnItemCountDescription => '显示文件夹内的项目数量';

  // Column visibility dialog
  @override
  String get columnVisibilityInstructions =>
      '选择要在详细信息视图中显示的列。'
      '“名称”列始终显示，无法禁用。';

  // List field visibility
  @override
  String get listFieldVisibilityTitle => '自定义列表字段';

  @override
  String get listFieldVisibilityInstructions => '选择要在列表视图中显示的字段。';

  // Metadata format strings
  @override
  String dimensionsFormat(int width, int height) => '$width × $height';

  @override
  String itemCountFormat(int count) => '$count 个项目';

  // Grid size dialog
  @override
  String gridSizeLabel(int count) => '项目大小级别：$count';

  @override
  String get gridSizeInstructions => '拖动滑块以调整项目大小';

  // More options menu
  @override
  String get selectMultipleFiles => '选择多个文件';

  @override
  String get selectMultipleTags => '选择多个标签';

  @override
  String get viewImageGallery => '查看图片库';

  @override
  String get viewVideoGallery => '查看视频库';

  // Navigation
  @override
  String get home => '主页';
  @override
  String get back => '返回';
  @override
  String get forward => '前进';
  @override
  String get refresh => '刷新';
  @override
  String get parentFolder => '上级文件夹';
  @override
  String get local => '本地';
  @override
  String get networks => '网络';

  // File types
  @override
  String get image => '图片';
  @override
  String get video => '视频';
  @override
  String get audio => '音频';
  @override
  String get document => '文档';
  @override
  String get folder => '文件夹';
  @override
  String get file => '文件';

  // File type labels
  @override
  String get fileTypeGeneric => '文件';
  @override
  String get fileTypeJpeg => 'JPEG 图片';
  @override
  String get fileTypePng => 'PNG 图片';
  @override
  String get fileTypeGif => 'GIF 图片';
  @override
  String get fileTypeBmp => 'BMP 图片';
  @override
  String get fileTypeTiff => 'TIFF 图片';
  @override
  String get fileTypeWebp => 'WebP 图片';
  @override
  String get fileTypeSvg => 'SVG 图片';
  @override
  String get fileTypeMp4 => 'MP4 视频';
  @override
  String get fileTypeAvi => 'AVI 视频';
  @override
  String get fileTypeMov => 'MOV 视频';
  @override
  String get fileTypeWmv => 'WMV 视频';
  @override
  String get fileTypeFlv => 'FLV 视频';
  @override
  String get fileTypeMkv => 'MKV 视频';
  @override
  String get fileTypeMp3 => 'MP3 音频';
  @override
  String get fileTypeWav => 'WAV 音频';
  @override
  String get fileTypeAac => 'AAC 音频';
  @override
  String get fileTypeFlac => 'FLAC 音频';
  @override
  String get fileTypeOgg => 'OGG 音频';
  @override
  String get fileTypePdf => 'PDF 文档';
  @override
  String get fileTypeWord => 'Word 文档';
  @override
  String get fileTypeExcel => 'Excel 表格';
  @override
  String get fileTypePowerPoint => 'PowerPoint 演示文稿';
  @override
  String get fileTypeTxt => '文本文件';
  @override
  String get fileTypeRtf => 'RTF 文档';
  @override
  String get fileTypeZip => 'ZIP 压缩文件';
  @override
  String get fileTypeRar => 'RAR 压缩文件';
  @override
  String get fileType7z => '7Z 压缩文件';
  @override
  String fileTypeWithExtension(String extension) => '$extension 文件';

  // File template type names
  @override
  String get fileTypeMarkdown => 'Markdown';
  @override
  String get fileTypeJson => 'JSON 文件';
  @override
  String get fileTypeHtml => 'HTML 文档';
  @override
  String get fileTypeCss => 'CSS 样式表';
  @override
  String get fileTypeDart => 'Dart 文件';
  @override
  String get fileTypePython => 'Python 脚本';
  @override
  String get fileTypeJavaScript => 'JavaScript';
  @override
  String get fileTypeTypeScript => 'TypeScript';
  @override
  String get fileTypeJava => 'Java 文件';
  @override
  String get fileTypeCpp => 'C++ 文件';
  @override
  String get fileTypeC => 'C 文件';
  @override
  String get fileTypeGo => 'Go 文件';
  @override
  String get fileTypeRust => 'Rust 文件';
  @override
  String get fileTypeXml => 'XML 文件';
  @override
  String get fileTypeYaml => 'YAML 文件';
  @override
  String get fileTypeShell => 'Shell 脚本';
  @override
  String get fileTypeCsv => 'CSV 表格';
  @override
  String get fileTypeLibreDoc => 'LibreOffice 文档';
  @override
  String get fileTypeLibreSheet => 'LibreOffice 表格';
  @override
  String get fileTypeLibrePresentation => 'LibreOffice 演示文稿';
  @override
  String get fileTypeLibreDraw => 'LibreOffice 绘图';
  @override
  String get fileTypeLibreChart => 'LibreOffice 图表';
  @override
  String get fileTypeLibreFormula => 'LibreOffice 公式';
  @override
  String get fileTypeWpsDoc => 'WPS 文档';
  @override
  String get fileTypeWpsSheet => 'WPS 表格';
  @override
  String get fileTypeWpsPresentation => 'WPS 演示文稿';
  @override
  String get fileTypeGoogleDoc => 'Google 文档';
  @override
  String get fileTypeGoogleSheet => 'Google 表格';
  @override
  String get fileTypeGoogleSlides => 'Google 幻灯片';
  @override
  String get fileTypeTar => 'TAR 压缩文件';
  @override
  String get fileTypeGzip => 'GZIP 压缩文件';

  // Settings
  @override
  String get language => '语言';
  @override
  String get theme => '主题';
  @override
  String get darkMode => '深色模式';
  @override
  String get lightMode => '浅色模式';
  @override
  String get systemMode => '跟随系统';
  @override
  String get selectLanguage => '选择您要使用的语言';
  @override
  String get selectTheme => '选择应用的显示主题';
  @override
  String get selectThumbnailPosition => '选择视频缩略图的截取位置';
  @override
  String get systemThemeDescription => '跟随系统主题设置';
  @override
  String get lightThemeDescription => '所有界面使用浅色';
  @override
  String get darkThemeDescription => '所有界面使用深色';
  @override
  String get themeOnboardingTitle => '选择您的主题';
  @override
  String get themeOnboardingDescription => '进入应用前，请选择默认外观。';
  @override
  String get themeOnboardingLightLabel => '浅色';
  @override
  String get themeOnboardingDarkLabel => '深色';
  @override
  String get themeOnboardingMoreThemesMessage => '更多主题可在“设置”中找到。';
  @override
  String get themeOnboardingContinue => '继续';
  @override
  String get accentColor => '强调色';
  @override
  String currentAccentColor(String name) => '当前强调色：$name';
  @override
  String get fontColor => '字体颜色';
  @override
  String currentFontColor(String name) => '当前字体颜色：$name';
  @override
  String get uiFont => '字体';
  @override
  String currentUiFont(String name) => '当前字体：$name';
  @override
  String get uiFontUnicodeHint =>
      '免费的 Unicode 字体（越南语 + 拉丁文扩展）。额外字体仅下载一次，并缓存在本地。';
  @override
  String get backdropMode => '背景模式';
  @override
  String get backdropModeDynamic => '动态';
  @override
  String get backdropModeWallpaper => '壁纸';
  @override
  String get backdropModeDynamicDescription => '正在使用系统动态亚克力背景。';
  @override
  String get backdropModeWallpaperDescription => '正在使用系统壁纸作为背景。';
  @override
  String get noSystemWallpaperDetected => '未检测到系统壁纸';
  @override
  String get customBackdropImage => '自定义';
  @override
  String get backdropImageNotFound => '未找到图片';
  @override
  String get backdropModeGlass => '玻璃';
  @override
  String get backdropModeGlassDescription => '透过 macOS 玻璃效果查看应用后方的桌面和窗口。';
  @override
  String get desktopGlassStrength => '玻璃透明度';
  @override
  String desktopGlassStrengthDescription(int percentage) =>
      '显示更多背景，同时保留文字后方的保护底色（$percentage%）。';
  @override
  String get desktopGlassBlur => '玻璃背景模糊';
  @override
  String desktopGlassBlurDescription(int percentage) =>
      '柔化玻璃表面后方的壁纸和内容（$percentage%）。';
  @override
  String get desktopAcrylicStrength => '桌面亚克力强度';
  @override
  String desktopAcrylicStrengthDescription(int percentage) =>
      '调整桌面背景的模糊和着色强度 ($percentage%)。';
  @override
  String get vietnameseLanguage => '越南语';
  @override
  String get englishLanguage => '英语';
  @override
  String get turkishLanguage => '土耳其语';
  @override
  String get chineseLanguage => '简体中文';
  @override
  String get languageOnboardingTitle => '选择您的语言';
  @override
  String get languageOnboardingDescription =>
      '选择 CB File Hub 使用的语言。您之后可以在“设置”中更改。';

  // Messages
  @override
  String get fileDeleteConfirmation => '确定要删除此文件吗？';
  @override
  String get folderDeleteConfirmation => '确定要删除此文件夹及其所有内容吗？';
  @override
  String get fileDeleteSuccess => '文件已成功删除';
  @override
  String get folderDeleteSuccess => '文件夹已成功删除';
  @override
  String get operationFailed => '操作失败';
  @override
  String get failedToCreateAlbum => '创建相册失败';
  @override
  String get failedToUpdateAlbum => '更新相册失败';

  // Tags
  @override
  String get tags => '标签';
  @override
  String get addTag => '添加标签';
  @override
  String get removeTag => '移除标签';
  @override
  String get tagListRefreshing => '正在刷新标签列表...';
  @override
  String get tagManagement => '标签管理';
  @override
  String get parentTagLabel => '父标签';
  @override
  String get childTagInputHint => '输入子标签…';
  @override
  String get copyTags => '复制标签';
  @override
  String exitTagScope(String parent) => '离开“$parent”';
  @override
  String childTagHint(String parent) => '在“$parent”中新建标签...';
  @override
  String addingUnderTag(String parent) => '正在向“$parent”添加子标签。按 Esc 离开此父标签。';
  @override
  String get tagInputHelp => '输入父标签，然后按“:”或 → 在其标签块内输入子标签。';
  @override
  String get tagSuggestionsLabel => '推荐标签';
  @override
  String childTagCount(int count) => '$count 个子标签';
  @override
  String deleteTagConfirmation(String tag) => '删除标签“$tag”？';
  @override
  String get tagDeleteConfirmationText => '这会从所有文件中移除该标签。此操作无法撤销。';
  @override
  String tagDeleted(String tag) => '标签“$tag”已成功删除';
  @override
  String errorDeletingTag(String error) => '删除标签时出错：$error';
  @override
  String chooseTagColor(String tag) => '为“$tag”选择颜色';
  @override
  String tagColorUpdated(String tag) => '标签“$tag”的颜色已更新';
  @override
  String get allTags => '所有标签';
  @override
  String get filesWithTag => '带有标签“%s”的文件';
  @override
  String get tagsInDirectory => '“%s”中的标签';
  @override
  String get aboutTags => '关于标签管理';
  @override
  String get aboutTagsTitle => '标签管理简介：';
  @override
  String get aboutTagsDescription =>
      '标签通过添加自定义标记来帮助您整理文件。'
      '您可以为文件添加或移除标签，并查找带有特定标签的所有文件。';
  @override
  String get aboutTagsScreenDescription =>
      '• 库中的所有标签\n'
      '• 带有所选标签的文件\n'
      '• 删除标签的选项';
  @override
  String get deleteTag => '从所有文件中删除此标签';
  @override
  String get deleteAlbum => '删除相册';

  // Tag Management Screen
  @override
  String get tagManagementTitle => '标签管理';
  @override
  String get debugTags => '调试标签';
  @override
  String get searchTags => '搜索';
  @override
  String get searchTagsHint => '搜索标签...';
  @override
  String get createNewTag => '新建标签';
  @override
  String get newTagTooltip => '新建标签';
  @override
  String get errorLoadingTags => '加载标签时出错：';
  @override
  String get noTagsFoundMessage => '未找到标签';
  @override
  String get noTagsFoundDescription => '新建标签以开始整理文件';
  @override
  String get createNewTagButton => '新建标签';
  @override
  String noMatchingTagsMessage(String searchTags) => '没有与“$searchTags”匹配的标签';
  @override
  String get clearSearch => '清除搜索';
  @override
  String get tagManagementHeader => '标签管理';
  @override
  String get tagsCreated => '个标签已创建';
  @override
  String get tagManagementDescription =>
      '点击标签即可查看带有该标签的所有文件。使用右侧的按钮可更改颜色或删除标签。';
  @override
  String get sortTags => '标签排序';
  @override
  String get sortByAlphabet => '按字母顺序';
  @override
  String get sortByPopular => '按热门程度';
  @override
  String get listViewMode => '列表模式';
  @override
  String get gridViewMode => '网格模式';
  @override
  String get treeViewMode => '树状模式';
  @override
  String get previousPage => '上一页';
  @override
  String get nextPage => '下一页';
  @override
  String get page => '页';
  @override
  String get firstPage => '首页';
  @override
  String get lastPage => '末页';
  @override
  String get clickToViewFiles => '点击查看文件';
  @override
  String get changeTagColor => '更改标签颜色';
  @override
  String get deleteTagFromAllFiles => '从所有文件中删除此标签';
  @override
  String get openInNewTab => '在新标签页中打开';
  @override
  String get viewFilesWithTag => '查看带有该标签的文件';
  @override
  String get setThumbnail => '设置缩略图';
  @override
  String get removeThumbnail => '移除缩略图';
  @override
  String get manageHierarchy => '管理层级';
  @override
  String get renameTag => '重命名标签';
  @override
  String tagRenamed(String oldTag, String newTag) =>
      '标签“$oldTag”已重命名为“$newTag”';
  @override
  String get openInSplitView => '在分屏中打开';
  @override
  String get changeColor => '更改颜色';
  @override
  String get noFilesWithTag => '未找到带有此标签的文件';
  @override
  String debugInfo(String tag) => '调试信息：正在搜索标签“$tag”';
  @override
  String get backToAllTags => '返回所有标签';
  @override
  String get tryAgain => '重试';
  @override
  String get filesWithTagCount => '个文件';
  @override
  String get viewDetails => '查看详情';
  @override
  String get openContainingFolder => '打开所在文件夹';
  @override
  String get editTags => '编辑标签';
  @override
  String get newTagTitle => '新建标签';
  @override
  String get enterTagName => '输入标签名称...';
  @override
  String get tagName => '标签名称';
  @override
  String get enterNewTagName => '输入新标签名称...';
  @override
  String tagAlreadyExists(String tagName) => '标签“$tagName”已存在';
  @override
  String tagCreatedSuccessfully(String tagName) => '标签“$tagName”创建成功';
  @override
  String get errorCreatingTag => '创建标签时出错：';
  @override
  String get tagsSavedSuccessfully => '标签保存成功';
  @override
  String get selectTagToRemove => '选择要移除的标签：';
  @override
  String get selectFilesToRemoveTags => '请选择要移除标签的文件';
  @override
  String get doubleClickToRename => '双击可重命名';
  @override
  String get openingFolder => '正在打开文件夹：';
  @override
  String get folderNotFound => '未找到文件夹：';
  @override
  String get refreshTags => '刷新标签';
  @override
  String tagsRefreshed(int count) => '标签已刷新 - 已加载 $count 个标签';
  @override
  String get tagManagementInfoTitle => '标签管理说明';
  @override
  String get tagManagementInfoDescription =>
      '在此界面中，您可以管理文件和文件夹的标签。\n\n'
      '• 查看所有标签\n'
      '• 搜索标签\n'
      '• 按名称或热门程度对标签排序\n'
      '• 查看分配了某个标签的文件';
  @override
  String removeTagsFromFilesTitle(int count) => '从 $count 个文件中移除标签';
  @override
  String get loadingTags => '正在加载标签...';
  @override
  String get noCommonTagsAcrossSelectedFiles => '所选文件没有共同的标签';
  @override
  String removeTagsSuccess(int removedTagCount, int fileCount) =>
      '已从 $fileCount 个文件中移除 $removedTagCount 个标签';
  @override
  String removeTagsError(String error) => '移除标签时出错：$error';
  @override
  String batchTagProcessingError(String error) => '处理标签时出错：$error';
  @override
  String searchError(String error) => '搜索出错：$error';

  // Gallery
  @override
  String get imageGallery => '图片库';
  @override
  String get videoGallery => '视频库';

  // Additional translations for database settings
  @override
  String get databaseSettings => '数据库设置';
  @override
  String get databaseStorage => '数据库存储';
  @override
  String get useDatabaseStorage => '使用 SQLite 数据库';
  @override
  String get databaseStorageEnabled => '使用 SQLite 实现高效的本地数据库存储';
  @override
  String get databaseDescription => '将标签和偏好设置存储在本地数据库中';
  @override
  String get jsonStorage => '使用 JSON 文件进行基本存储';
  @override
  String get objectBoxStorage => '使用 SQLite 实现高效的本地数据库存储'; // Legacy

  // Cloud sync
  @override
  String get cloudSync => '云同步';
  @override
  String get enableCloudSync => '启用云同步';
  @override
  String get cloudSyncDescription => '将标签和偏好设置同步到云端';
  @override
  String get syncToCloud => '同步到云端';
  @override
  String get syncFromCloud => '从云端同步';
  @override
  String get cloudSyncEnabled => '标签和偏好设置将同步到云端';
  @override
  String get cloudSyncDisabled => '云同步已禁用';
  @override
  String get syncToCloudSuccess => '已成功同步到云端';
  @override
  String get syncToCloudFailed => '同步到云端失败';
  @override
  String get syncFromCloudSuccess => '已成功从云端同步';
  @override
  String get syncFromCloudFailed => '从云端同步失败';
  @override
  String get enableDatabaseForCloud => '请启用 SQLite 数据库以使用云同步';
  @override
  String get backupAndSync => '备份与同步';
  @override
  String get chooseCloudSyncFolder => '选择同步文件夹';
  @override
  String get cloudBackupNotFound => '未找到云备份';
  @override
  String get cloudProvider => '云服务';
  @override
  String get cloudProviderNotConfigured => '此版本不可用（编译时未包含 OAuth 客户端 ID）';
  @override
  String get localSyncFolder => '本地同步文件夹';
  @override
  String get localSyncFolderDescription => '将存档写入桌面同步应用已在镜像的文件夹中';
  @override
  String get openingBrowserToSignIn => '正在打开浏览器以登录...';
  @override
  String connectedAsAccount(String account) => '已连接为 $account';
  @override
  String cloudBackupsStoredIn(String folder) => '备份保存在 $folder';
  @override
  String get chooseBackupToRestore => '选择要恢复的备份';
  @override
  String get noCloudBackupsYet => '此云盘上还没有备份';
  @override
  String get uploadingBackup => '正在上传备份...';
  @override
  String get downloadingBackup => '正在下载备份...';
  @override
  String backupUploadedTo(String provider) => '备份已上传到 $provider';
  @override
  String get deleteCloudBackupConfirm => '要从云盘中删除此备份吗？';
  @override
  String get connectCloudFirst => '请先连接云服务';
  @override
  String get syncAllClouds => '备份到所有已连接的云盘';
  @override
  String cloudConnectedCount(int connected, int total) =>
      '已连接 $connected / $total 个云盘';
  @override
  String get cloudStatusConnected => '已连接';
  @override
  String get cloudStatusUnavailable => '不可用';
  @override
  String get cloudStatusFailed => '失败';
  @override
  String get waitingForSignIn => '正在等待在浏览器中登录...';
  @override
  String lastBackupAt(String time) => '上次备份：$time';
  @override
  String lastBackupFailedAt(String time, String error) => '备份失败（$time）：$error';
  @override
  String get neverBackedUpHere => '此设备尚未备份';
  @override
  String syncAllResult(int succeeded, int total) =>
      '已备份到 $succeeded / $total 个云盘';
  @override
  String get backUpNow => '备份';
  @override
  String get restoreBackup => '恢复';

  // Database statistics
  @override
  String get databaseStatistics => '数据库统计';
  @override
  String get totalUniqueTags => '标签总数（去重）';
  @override
  String get taggedFiles => '已加标签的文件';
  @override
  String get popularTags => '最热门标签';
  @override
  String get recentTags => '最近的标签';
  @override
  String get selectedTags => '已选标签：';
  @override
  String batchAddTags(int count) => '为 $count 个文件添加标签';
  @override
  String get applyingChanges => '正在应用更改...';
  @override
  String tagsUpdated(int count, int added, int removed) {
    var msg = '已更新 $count 个文件的标签';
    final parts = <String>[];
    if (added > 0) parts.add('添加 $added');
    if (removed > 0) parts.add('移除 $removed');
    if (parts.isNotEmpty) msg += '（${parts.join('，')}）';
    return msg;
  }

  @override
  String get tagSuggestions => '标签建议';
  @override
  String get advancedDatabaseSettings => '高级数据库设置';
  @override
  String get noTagsFound => '未找到标签';
  @override
  String get refreshStatistics => '刷新统计';

  // Raw Data Viewer
  @override
  String get viewRawData => '查看原始数据';
  @override
  String get rawDataPreferences => '偏好设置';
  @override
  String get rawDataTags => '文件标签';
  @override
  String get rawDataDescription => '查看数据库中存储的原始数据（用于调试）';
  @override
  String get noDataFound => '未找到数据';

  // Import/Export
  @override
  String get importExportDatabase => '导入/导出数据库';
  @override
  String get backupRestoreDescription => '备份和恢复您的标签及文件关联';
  @override
  String get exportDatabase => '导出数据库';
  @override
  String get exportSettings => '导出设置';
  @override
  String get importDatabase => '导入数据库';
  @override
  String get importSettings => '导入设置';
  @override
  String get resetSettings => '重置设置';
  @override
  String get exportDescription => '将标签保存到文件';
  @override
  String get importDescription => '从文件恢复标签';
  @override
  String get completeBackup => '完整备份';
  @override
  String get completeRestore => '完整恢复';
  @override
  String get exportAllData => '导出所有设置和数据库数据';
  @override
  String get importAllData => '导入所有设置和数据库数据';

  // Export/Import messages
  @override
  String get exportSuccess => '已成功导出到：';
  @override
  String get exportFailed => '导出失败';
  @override
  String get importSuccess => '导入成功';
  @override
  String get importFailed => '导入失败或已取消';
  @override
  String get importCancelled => '导入已取消';
  @override
  String get errorExporting => '导出时出错：';
  @override
  String get errorImporting => '导入时出错：';
  @override
  String get backupAndRestore => '备份与恢复';
  @override
  String get backupRestoreHint =>
      '将标签和偏好设置备份为 .db 文件（快速、可扩展），或将偏好设置导出为 JSON（便于阅读）。';
  @override
  String get exportSqlite => '导出 SQLite';
  @override
  String get exportSqliteDesc => '快速备份 (.db) — 标签 + 偏好设置';
  @override
  String get exportJson => '导出 JSON';
  @override
  String get exportJsonDesc => '将偏好设置导出为可读的 JSON';
  @override
  String get importBackup => '导入备份';
  @override
  String get importBackupDesc => '自动识别 .db 或 .json 文件';
  @override
  String get exporting => '正在导出...';
  @override
  String get importing => '正在导入...';
  @override
  String get sharedPreferences => 'SharedPreferences';
  @override
  String get sharedPreferencesDesc => '查看并清除应用的键值设置';
  @override
  String get clearSharedPreferencesConfirm => '清除所有 SharedPreferences？';
  @override
  String get deleteKeyConfirm => '删除此键？';
  @override
  String get clear => '清除';
  @override
  String get sharedPreferencesCleared => 'SharedPreferences 已清除。';
  @override
  String get deletedKey => '已删除：';
  @override
  String get copied => '已复制：';
  @override
  String tagsImported(int count) => '已导入 $count 个标签';
  @override
  String settingsRestored(int count) => '已恢复 $count 项设置';
  @override
  String get saveBackup => '保存备份';
  @override
  String get exportPreferencesAsJson => '将偏好设置导出为 JSON';
  @override
  String get exportBackupZip => '将备份导出为 ZIP';
  @override
  String get exportBackupZipDesc => '选择要包含的设置和标签';
  @override
  String get importBackupZip => '导入备份 ZIP';
  @override
  String get importBackupZipDesc => '选择要恢复的部分';
  @override
  String get backupSettingsPart => '设置';
  @override
  String get backupTagsPart => '标签';
  @override
  String get continueText => '继续';
  @override
  String get sharedPreferencesKeyRemoved => '设置已从 SharedPreferences 中移除。';
  @override
  String get jsonCopiedToClipboard => 'JSON 已复制到剪贴板';
  @override
  String get copyValue => '复制值';
  @override
  String get deleteKey => '删除键';
  @override
  String get copyJson => '复制 JSON';
  @override
  String get viewJson => '查看 JSON';
  @override
  String get clearAll => '全部清除';

  // Video thumbnails
  @override
  String get videoThumbnails => '视频缩略图';
  @override
  String get thumbnailMode => '生成模式';
  @override
  String get thumbnailModeFast => '快速';
  @override
  String get thumbnailModeCustom => '自定义';
  @override
  String get thumbnailModeFastDescription => '使用系统内置方法。速度更快，但位置固定。';
  @override
  String get thumbnailModeCustomDescription => '使用 FFmpeg 在指定位置截取。速度较慢，但可控性更强。';
  @override
  String get thumbnailPosition => '缩略图位置：';
  @override
  String get generatingAtPosition => '截取位置';
  @override
  String get generatingFast => '快速模式';
  @override
  String get maxConcurrency => '最大并行任务数';
  @override
  String get maxConcurrencyDescription => '数值越大，缩略图生成越快，但占用的 CPU 也越多';
  @override
  String get percentOfVideo => '% 视频时长处';
  @override
  String get thumbnailDescription => '设置在视频的哪个位置（占总时长的百分比）截取缩略图';
  @override
  String get useSystemDefaultForVideo => '使用系统默认应用播放视频';
  @override
  String get useSystemDefaultForVideoDescription =>
      '开启后，点击视频将使用系统默认应用打开。关闭后，使用应用内播放器。';
  @override
  String get useSystemDefaultForVideoEnabled => '视频将使用系统默认应用打开';
  @override
  String get useSystemDefaultForVideoDisabled => '视频将在应用内播放器中打开';
  @override
  String get seekSpeed => '快进快退速度';
  @override
  String get seekSpeedDescription => '按住快进快退键或在移动端长按时，视频跳转的速度';
  @override
  String get seekSpeedSlow => '慢';
  @override
  String get seekSpeedMedium => '中';
  @override
  String get seekSpeedFast => '快';
  @override
  String get videoWheelAction => '视频上的鼠标滚轮';
  @override
  String get videoWheelActionDescription => '在播放器上滚动鼠标滚轮的功能。在视频上单击鼠标中键可切换。';
  @override
  String get videoWheelVolume => '音量';
  @override
  String get videoWheelSeek => '快进快退';
  @override
  String videoWheelModeSwitched(String mode) => '鼠标滚轮：$mode';
  @override
  String videoWheelSwitchHint(String mode) => '单击鼠标中键切换为$mode';
  @override
  String get videoDecoding => '视频解码';
  @override
  String get videoDecodingAuto => '自动（推荐）';
  @override
  String get videoDecodingGpu => '始终使用 GPU';
  @override
  String get videoDecodingCpu => '始终使用 CPU';
  @override
  String get videoDecodingAutoDescription =>
      '使用此设备内置的 GPU 解码器，播放更流畅且更省电。GPU 解码失败时会回退到 CPU。';
  @override
  String get videoDecodingAutoDescriptionWindows =>
      '大多数视频使用 CPU，4K 视频切换为 GPU，以保持跳转流畅。GPU 解码失败时会回退到 CPU。';
  @override
  String get videoDecodingGpuDescription =>
      '所有视频均在显卡上解码。对 CPU 负担最小，但部分驱动可能出错；出错时播放会切换到 CPU。';
  @override
  String get videoDecodingCpuDescription => '适用于所有设备，但 4K 视频跳转较慢，且占用更多 CPU。';
  @override
  String get videoDecodingReopenHint => '下次打开视频时完全生效。';
  @override
  String get videoDecodingFellBackToCpu =>
      'GPU 无法解码此视频，播放已切换到 CPU。您可以在“视频”设置中更改此选项。';
  @override
  String get openVideoInNewWindow => '在单独的窗口中打开视频';
  @override
  String get openVideoInNewWindowDescription =>
      '仅限桌面端。使用同一个独立的应用内播放器窗口；打开另一个视频时会替换该窗口中当前的视频。';
  @override
  String get openVideoInNewWindowEnabled => '视频将在单独的播放器窗口中打开';
  @override
  String get openVideoInNewWindowDisabled => '视频播放器将在当前窗口中打开';
  @override
  String get thumbnailCache => '缩略图缓存';
  @override
  String get thumbnailCacheDescription =>
      '视频缩略图会被缓存以提升性能。如果缩略图已过时，或您想释放空间，可以清除缓存。';
  @override
  String get clearThumbnailCache => '清除缩略图缓存';
  @override
  String get clearing => '正在清除...';
  @override
  String get thumbnailCleared => '所有视频缩略图已清除';
  @override
  String get errorClearingThumbnail => '清除缩略图时出错：';

  // New tab
  @override
  String get newTab => '新建标签页';

  // Admin access
  @override
  String get adminAccess => '管理员访问';
  @override
  String get adminAccessRequired => '访问此驱动器需要管理员权限';
  @override
  String get requiresAdminPrivileges => '需要管理员权限';
  @override
  String driveRequiresAdmin(String path) => '访问驱动器 $path 需要管理员权限。';
  @override
  String get trashBin => '回收站';

  // File system
  @override
  String get drives => '驱动器';
  @override
  String get system => '系统';

  // Settings data
  @override
  String get settingsData => '设置数据';
  @override
  String get viewManageSettings => '查看和管理设置数据';

  // About app
  @override
  String get aboutApp => '关于应用';
  @override
  String get appDescription => '高级文件管理解决方案';
  @override
  String get version => '版本';
  @override
  String get developer => '开发者';

  // Empty state
  @override
  String get emptyFolder => '空文件夹';
  @override
  String get noImagesFound => '此文件夹中没有图片';
  @override
  String get noVideosFound => '此文件夹中没有视频';
  @override
  String get loading => '正在加载...';

  // File picker dialogs
  @override
  String get chooseBackupLocation => '选择备份位置';
  @override
  String get chooseRestoreLocation => '选择恢复文件';
  @override
  String get saveSettingsExport => '保存导出的设置';
  @override
  String get saveDatabaseExport => '保存导出的数据库';
  @override
  String get selectBackupFolder => '选择备份文件夹';

  // File details
  @override
  String get fileSize => '大小';
  @override
  String get fileLocation => '位置';
  @override
  String get fileCreated => '创建时间';
  @override
  String get fileModified => '修改时间';
  @override
  String get fileName => '文件名';
  @override
  String get filePath => '文件路径';
  @override
  String get fileType => '文件类型';
  @override
  String get fileLastModified => '最后修改';
  @override
  String get fileAccessed => '访问时间';
  @override
  String get loadingVideo => '正在加载视频...';
  @override
  String get errorLoadingImage => '加载图片时出错';
  @override
  String errorLoadingImageWithError(String error) => '加载图片时出错：$error';
  @override
  String get failedToDisplayImage => '无法显示图片';
  @override
  String get noImageDataAvailable => '没有可用的图片数据';
  @override
  String get urlLoadingNotImplemented => '尚未支持通过网址加载';
  @override
  String get duration => '时长';
  @override
  String get resolution => '分辨率';
  @override
  String get createCopy => '创建副本';
  @override
  String get deleteFile => '删除文件';

  // Folder thumbnails
  @override
  String get folderThumbnail => '文件夹缩略图';
  @override
  String get chooseThumbnail => '选择缩略图';
  @override
  String get cropImage => '裁剪图片';
  @override
  String get applyCrop => '应用';
  @override
  String get useOriginal => '使用原图';
  @override
  String get aspectFree => '自由';
  @override
  String get tagGridCropRecommendation => '标签网格卡片推荐：16:9，至少 1280 × 720 px';
  @override
  String get tagGridAspectPreset => '16:9 · 标签网格';
  @override
  String get clearThumbnail => '清除缩略图';
  @override
  String get thumbnailAuto => '自动（第一个视频/图片）';
  @override
  String get folderThumbnailSet => '文件夹缩略图已更新';
  @override
  String get folderThumbnailCleared => '文件夹缩略图已清除';
  @override
  String get invalidThumbnailFile => '请选择图片或视频文件';
  @override
  String get noMediaFilesFound => '此文件夹中没有媒体文件';

  // Video actions
  @override
  String get share => '分享';
  @override
  String get playVideo => '播放视频';
  @override
  String get videoInfo => '视频信息';
  @override
  String get deleteVideo => '删除视频';
  @override
  String get loadingThumbnails => '正在加载缩略图';
  @override
  String get deleteVideosConfirm => '删除视频？';
  @override
  String get deleteConfirmationMessage => '确定要删除所选视频吗？此操作无法撤销。';
  @override
  String videosSelected(int count) => '已选择 $count 个视频';
  @override
  String videosDeleted(int count) => '已删除 $count 个视频';
  @override
  String searchingFor(String query) => '正在搜索：“$query”';
  @override
  String get errorDisplayingVideoInfo => '无法显示视频信息';
  @override
  String get searchVideos => '搜索视频';
  @override
  String get enterVideoName => '输入视频名称...';

  // Selection and grid
  @override
  String? get selectMultiple => '选择多个文件';
  @override
  String? get gridSize => '网格大小';

  @override
  String get searchOrEnterPath => '搜索或输入路径';

  @override
  String get pleaseCreateTabFirst => '请先创建一个标签页';

  @override
  String get viewMode => '视图模式';

  @override
  String get masonryLayout => '瀑布流布局 (Pinterest)';

  // Sorting
  @override
  String get sort => '排序';
  @override
  String get sortByName => '按名称排序';
  @override
  String get sortByPopularity => '按热门程度排序';
  @override
  String get sortByRecent => '按最近使用排序';
  @override
  String get sortBySize => '按大小排序';
  @override
  String get sortByDate => '按日期排序';
  @override
  String get viewModeFeatureComingSoon => '视图模式切换将在稍后添加';
  @override
  String get cannotCreateFileInThisLocation => '无法在此位置创建文件';

  // Bulk Selection
  @override
  String get bulkSelect => '批量选择';
  @override
  String get selectAllTags => '全选';
  @override
  String selectAllOnAllPages(int totalCount) => '全选（$totalCount 个标签）';
  @override
  String get deselectAllTags => '取消全选';
  @override
  String tagsSelected(int count) => '已选择 $count 个标签';
  @override
  String bulkDeleteConfirmationTitle() => '删除所选标签？';
  @override
  String bulkDeleteConfirmationText(int count) => '确定要删除 $count 个标签吗？此操作无法撤销。';
  @override
  String bulkDeleteSuccess(int count) => '已成功删除 $count 个标签';

  // Search errors
  @override
  String noFilesFoundTag(Map<String, String> args) =>
      '未找到带有标签“${args['tag']}”的文件';

  @override
  String noFilesFoundTagGlobal(Map<String, String> args) =>
      '在全局范围内未找到带有标签“${args['tag']}”的文件';

  @override
  String noFilesFoundTags(Map<String, String> args) =>
      '未找到带有标签 ${args['tags']} 的文件';

  @override
  String noFilesFoundTagsGlobal(Map<String, String> args) =>
      '在全局范围内未找到带有标签 ${args['tags']} 的文件';

  @override
  String noFilesFoundQuery(Map<String, String> args) =>
      '未找到“${args['query']}”的结果';

  @override
  String errorSearchTag(Map<String, String> args) =>
      '按标签搜索时出错：${args['error']}';

  @override
  String errorSearchTagGlobal(Map<String, String> args) =>
      '全局按标签搜索时出错：${args['error']}';

  @override
  String errorSearchTags(Map<String, String> args) =>
      '按多个标签搜索时出错：${args['error']}';

  @override
  String errorSearchTagsGlobal(Map<String, String> args) =>
      '全局按多个标签搜索时出错：${args['error']}';

  // Search status
  @override
  String searchingTag(Map<String, String> args) => '正在搜索标签“${args['tag']}”...';

  @override
  String searchingTagGlobal(Map<String, String> args) =>
      '正在全局搜索标签“${args['tag']}”...';

  @override
  String searchingTags(Map<String, String> args) => '正在搜索标签 ${args['tags']}...';

  @override
  String searchingTagsGlobal(Map<String, String> args) =>
      '正在全局搜索标签 ${args['tags']}...';

  // Search UI
  @override
  String get searchTips => '搜索技巧';

  @override
  String get searchTipsTitle => '搜索技巧';

  @override
  String get viewTagSuggestions => '查看标签建议';

  @override
  String get globalSearchModeEnabled => '已切换到子文件夹搜索';

  @override
  String get localSearchModeEnabled => '已切换到当前文件夹搜索';

  @override
  String get globalSearchMode => '正在子文件夹中搜索（点击切换）';

  @override
  String get localSearchMode => '正在当前文件夹中搜索（点击切换）';

  @override
  String get searchByFilename => '按文件名搜索';

  @override
  String get searchByTags => '按标签搜索';

  @override
  String get searchMultipleTags => '搜索多个标签';

  @override
  String get globalSearch => '子文件夹搜索';

  @override
  String get searchByNameOrTag => '按名称或 #标签 搜索';

  @override
  String get searchInSubfolders => '在子文件夹中搜索';

  @override
  String get featureNotImplemented => '此功能即将推出';

  @override
  String get searchInAllFolders => '在当前文件夹及其子文件夹中搜索';

  @override
  String get searchInCurrentFolder => '仅在当前文件夹中搜索';

  @override
  String get searchShortcuts => '快捷键';

  @override
  String get regexMode => '正则模式';

  @override
  String get regexModeEnabled => '正则模式已启用';

  @override
  String get regexModeDisabled => '正则模式已禁用';

  @override
  String get searchHintText => '搜索文件，或使用 # 按标签搜索';

  @override
  String get searchHintTextTags => '按标签搜索...（例如 #重要 #工作）';

  @override
  String get suggestedTags => '推荐标签';

  @override
  String get noMatchingTags => '未找到匹配的标签';

  @override
  String get results => '个结果';

  @override
  String searchResultsTitle(String countText) => '搜索结果$countText';

  @override
  String searchResultsTitleForQuery(String query, String countText) =>
      '“$query”的搜索结果$countText';

  @override
  String searchResultsTitleForTag(String tag, String countText) =>
      '标签“$tag”的搜索结果$countText';

  @override
  String searchResultsTitleForTagGlobal(String tag, String countText) =>
      '标签“$tag”的全局搜索结果$countText';

  @override
  String searchResultsTitleForFilter(String filter, String countText) =>
      '“$filter”的筛选结果$countText';

  @override
  String searchResultsTitleForMedia(String mediaType, String countText) =>
      '$mediaType的搜索结果$countText';

  @override
  String get searchByFilenameDesc => '输入要搜索的文件名。';

  @override
  String get searchByTagsDesc => '使用 # 符号按标签搜索。例如：#重要';

  @override
  String get searchMultipleTagsDesc =>
      '同时使用多个标签可以更精确地筛选结果。每个标签开头都需要 # 符号，并以空格分隔。例如：#工作 #紧急 #2023';

  @override
  String get globalSearchDesc => '点击文件夹/地球图标，可在仅搜索当前文件夹与包含子文件夹的搜索之间切换。';

  @override
  String get regexSearchDesc =>
      '启用正则模式 ({ }) 后，可使用正则表达式匹配名称。\n'
      '基本示例：\n'
      '• 以“img_”开头：^img_.*\n'
      '• 以 .mp4 结尾：.*\\.mp4\$\n'
      '• 包含“invoice”：.*invoice.*\n'
      '• 恰好 4 位数字：^\\d{4}\$\n'
      '• 带年份的报告：^report_\\d{4}\\.pdf\$';

  @override
  String get searchShortcutsDesc => '按 Enter 开始搜索。使用方向键从建议中选择标签。';

  // File operations related to networks
  @override
  String get download => '下载';
  @override
  String get downloadFile => '下载文件';
  @override
  String get selectDownloadLocation => '选择文件的保存位置：';
  @override
  String get selectFolder => '选择文件夹';
  @override
  String get browse => '浏览...';
  @override
  String get upload => '上传文件';
  @override
  String get uploadFile => '上传文件';
  @override
  String get selectFileToUpload => '选择要上传的文件：';
  @override
  String get create => '创建';
  @override
  String get folderName => '文件夹名称';

  // Permissions
  @override
  String get grantPermissionsToContinue => '授予权限以继续';

  @override
  String get permissionsDescription => '为了流畅使用应用，请授予以下权限。您也可以先跳过，稍后在“设置”中授予。';

  @override
  String get storagePermissionRequiredMessage =>
      '查看文件夹内容需要访问所有文件的权限。请前往“设置”>“应用”>“CB File Hub”>“权限”，并启用“所有文件访问权限”。';

  @override
  String get storagePhotosPermission => '存储/照片权限';

  @override
  String get storagePhotosDescription => '应用需要访问照片/文件，才能显示和播放本地内容。';

  @override
  String get allFilesAccessPermission => '所有文件访问权限（重要）';

  @override
  String get allFilesAccessDescription =>
      '需要此权限才能显示“下载”文件夹中的所有文件，包括 APK、文档和其他文件。';

  @override
  String get allFilesAccessDescriptionMacos =>
      'macOS 需要“完全磁盘访问权限”，应用才能浏览所有文件夹和驱动器。点击“授予权限”，将 CB File Hub 图标拖入打开的列表，并通过 Touch ID 或密码确认，然后选择“退出并重新打开”。';

  @override
  String get fullDiskAccessHelperTitle => '将 CB File Hub 拖入列表';

  @override
  String get fullDiskAccessHelperMessage =>
      '将此图标拖入“完全磁盘访问权限”列表，然后通过 Touch ID 或密码确认。如果列表中已有 CB File Hub，只需将其打开即可。';

  @override
  String get installPackagesPermission => '安装应用包 (APK)';

  @override
  String get installPackagesDescription => '需要此权限才能通过软件包安装程序打开并安装 APK 文件。';

  @override
  String get localNetworkPermission => '本地网络';

  @override
  String get localNetworkDescription => '允许访问本地网络，以浏览同一网络中的 SMB/NAS。';

  @override
  String get notificationsPermission => '通知（可选）';

  @override
  String get notificationsDescription => '启用通知以接收播放更新和后台任务消息。';

  @override
  String get grantAllPermissions => '授予所有权限';

  @override
  String get grantingPermissions => '正在授予权限...';

  @override
  String get enterApp => '进入应用';

  @override
  String get skipEnterApp => '跳过，进入应用';

  @override
  String get granted => '已授予';

  @override
  String get grantPermission => '授予权限';

  // Home screen
  @override
  String get welcomeToFileManager => '欢迎使用 CB File Hub';

  @override
  String get welcomeDescription => '您强大的文件管理助手';

  @override
  String get quickActions => '快捷操作';

  @override
  String get browseFiles => '浏览文件';

  @override
  String get browseFilesDescription => '浏览您的本地文件和文件夹';

  @override
  String get manageMedia => '管理媒体';

  @override
  String get manageMediaDescription => '在图库中查看图片和视频';

  @override
  String get tagFiles => '为文件加标签';

  @override
  String get tagFilesDescription => '使用智能标签整理文件';

  @override
  String get networkAccess => '网络访问';

  @override
  String get networkAccessDescription => '浏览网络驱动器和共享';

  @override
  String get keyFeatures => '主要功能';

  @override
  String get fileManagement => '文件管理';

  @override
  String get fileManagementDescription => '轻松浏览和整理您的文件';

  @override
  String get smartTagging => '智能标签';

  @override
  String get smartTaggingDescription => '为文件添加标签，实现闪电般的搜索';

  @override
  String get mediaGallery => '媒体库';

  @override
  String get mediaGalleryDescription => '精美的图片和视频图库';

  @override
  String get networkSupport => '网络支持';

  @override
  String get networkSupportDescription => '无缝访问网络驱动器';

  // Settings screen
  @override
  String get interface => '界面';

  @override
  String get selectInterfaceTheme => '选择界面和喜爱的颜色';

  @override
  String get chooseInterface => '选择界面';

  @override
  String get interfaceDescription => '多种颜色和样式';

  @override
  String get showFileTags => '显示文件标签';

  @override
  String get showFileTagsDescription => '在所有视图模式下，于文件列表之外显示文件标签';

  @override
  String get showFileTagsToggle => '显示文件标签';

  @override
  String get showFileTagsToggleDescription => '启用/禁用在文件列表之外显示标签';

  @override
  String get fileThumbnailFit => '文件缩略图显示方式';

  @override
  String get fileThumbnailFitDescription => '选择文件缩略图是填满边框还是显示完整图片';

  @override
  String get tagThumbnailFit => '标签缩略图显示方式';

  @override
  String get tagThumbnailFitDescription => '选择标签缩略图是显示完整图片还是填满边框';

  @override
  String get thumbnailFitContain => '显示完整图片';

  @override
  String get thumbnailFitCover => '填满边框';

  @override
  String get rememberTabWorkspace => '记住标签页工作区';

  @override
  String get rememberTabWorkspaceDescription => '恢复上次打开的标签页，并按标签页保留侧栏的折叠状态。';

  @override
  String get tabInactiveThreshold => '标签页闲置超时';

  @override
  String get tabInactiveThresholdDescription =>
      '标签页闲置达到此时长后，将自动挂起并释放其缓存。设为“关闭”则让标签页始终保持活动。';

  @override
  String get tabInactiveThresholdDisabled => '关闭';

  @override
  String get tabInactiveThresholdMinutesValue => '分钟';

  @override
  String get tabInactiveThresholdHoursValue => '小时';

  @override
  String get cacheManagement => '缓存管理';

  @override
  String get cacheManagementDescription => '清除缓存数据以释放内存';

  @override
  String get appDataManagement => '应用数据管理';

  @override
  String get appDataManagementDescription => '查看并清除缓存和已存储的应用数据';

  @override
  String get documentsData => '已存储数据';

  @override
  String get documentsDataDescription => '保存在“文档”中的持久文件，清理缓存时不会被删除';

  @override
  String get tagThumbnails => '标签缩略图';

  @override
  String get tagThumbnailsDescription => '您选作标签缩略图的图片（已提取的视频帧）';

  @override
  String get clearTagThumbnails => '清除标签缩略图';

  @override
  String get tagThumbnailsCleared => '标签缩略图已清除';

  @override
  String get documentsRoot => '文档根目录';

  @override
  String get cacheFolder => '缓存文件夹：';

  @override
  String get networkThumbnails => '网络缩略图：';

  @override
  String get videoThumbnailsCache => '视频缩略图：';

  @override
  String get tempFiles => '临时文件：';

  @override
  String get videoLibraryCache => '视频库缓存：';

  @override
  String get clearVideoLibraryCache => '清除视频库缓存';

  @override
  String get videoLibraryCacheCleared => '视频库缓存已清除';

  @override
  String get notInitialized => '未初始化';

  @override
  String get refreshCacheInfo => '刷新';

  @override
  String get cacheInfoUpdated => '缓存信息已更新';

  @override
  String get clearVideoThumbnailsCache => '清除视频缩略图缓存';

  @override
  String get clearVideoThumbnailsDescription => '清除已生成的视频缩略图';

  @override
  String get clearNetworkThumbnailsCache => '清除 SMB/网络缩略图缓存';

  @override
  String get clearNetworkThumbnailsDescription => '清除已生成的网络缩略图';

  @override
  String get clearTempFilesCache => '清除临时文件';

  @override
  String get clearTempFilesDescription => '清除网络共享中的临时文件';

  @override
  String get clearAllCache => '清除所有缓存';

  @override
  String get clearAllCacheDescription => '清除所有缓存数据';

  @override
  String get videoCacheCleared => '视频缩略图缓存已清除';

  @override
  String get networkCacheCleared => '网络缩略图缓存已清除';

  @override
  String get tempFilesCleared => '临时文件已清除';

  @override
  String get allCacheCleared => '所有缓存数据已清除';

  @override
  String get errorClearingCache => '错误：';

  // Clipboard actions
  @override
  String copiedToClipboard(String name) => '已将“$name”复制到剪贴板';
  @override
  String cutToClipboard(String name) => '已将“$name”剪切到剪贴板';
  @override
  String get pasting => '正在粘贴...';

  // Rename dialogs
  @override
  String get renameFileTitle => '重命名文件';
  @override
  String get renameFolderTitle => '重命名文件夹';
  @override
  String currentNameLabel(String name) => '当前名称：$name';
  @override
  String get newNameLabel => '新名称';

  @override
  String get renameShortcutHint => '按 Enter 保存 · 按 Esc 取消';

  @override
  String get renameNameRequired => '名称不能为空';

  @override
  String get renameInvalidCharacters => '名称不能包含 \\ / : * ? " < > |';

  @override
  String renamedFileTo(String newName) => '文件已重命名为“$newName”';
  @override
  String renamedFolderTo(String newName) => '文件夹已重命名为“$newName”';
  @override
  String get allowFileExtensionRename => '允许编辑文件扩展名';

  // Downloads
  @override
  String downloadedTo(String location) => '已下载到 $location';
  @override
  String downloadFailed(String error) => '下载失败：$error';

  // Folder / Trash
  @override
  String get items => '项目';

  @override
  String get files => '文件';

  @override
  String get deleteTitle => '删除';

  @override
  String get permanentDeleteTitle => '永久删除';

  @override
  String confirmDeletePermanent(String name) => '确定要永久删除“$name”吗？此操作无法撤销。';

  @override
  String confirmDeletePermanentMultiple(int count) =>
      '确定要永久删除 $count 个项目吗？此操作无法撤销。';

  @override
  String movedToTrash(String name) => '$name 已移到回收站';
  @override
  String moveItemsToTrashConfirmation(int count, String itemType) =>
      '要将 $count 个$itemType移到回收站吗？';
  @override
  String get moveItemsToTrashDescription => '这些项目将被移到回收站。如有需要，您之后可以恢复它们。';
  @override
  String get clearFilter => '清除筛选';
  @override
  String filteredBy(String filter) => '筛选条件：$filter';
  @override
  String noFilesMatchFilter(String filter) => '没有文件符合筛选条件“$filter”';

  // Trash / Recycle Bin screen
  @override
  String get emptyTrash => '清空回收站';
  @override
  String get emptyingTrash => '正在清空回收站…';
  @override
  String get emptyTrashConfirm => '确定要永久删除回收站中的所有项目吗？此操作无法撤销。';
  @override
  String get emptyTrashButton => '清空回收站';
  @override
  String permanentlyDeleteItemsTitle(int count) => '永久删除 $count 个项目？';
  @override
  String get confirmPermanentlyDeleteThese => '此操作无法撤销。确定要永久删除这些项目吗？';
  @override
  String itemRestoredSuccess(String name) => '$name 已成功恢复';
  @override
  String failedToRestore(String name) => '恢复 $name 失败';
  @override
  String errorRestoringItemWithError(String error) => '恢复项目时出错：$error';
  @override
  String itemPermanentlyDeleted(String name) => '$name 已永久删除';
  @override
  String failedToDelete(String name) => '删除 $name 失败';
  @override
  String failedToDeleteFilesCount(int count) => '删除 $count 个文件失败';
  @override
  String failedToDeleteItemsCount(int count) => '删除 $count 个项目失败';
  @override
  String errorDeletingItemWithError(String error) => '删除项目时出错：$error';
  @override
  String get trashEmptiedSuccess => '回收站已成功清空';
  @override
  String get failedToEmptyTrash => '清空回收站失败';
  @override
  String errorEmptyingTrashWithError(String error) => '清空回收站时出错：$error';
  @override
  String itemsRestoredSuccess(int count) => '已成功恢复 $count 个项目';
  @override
  String itemsRestoredWithFailures(int success, int failed) =>
      '已成功恢复 $success 个项目，$failed 个失败';
  @override
  String itemsPermanentlyDeletedCount(int count) => '已永久删除 $count 个项目';
  @override
  String itemsDeletedWithFailures(int success, int failed) =>
      '已永久删除 $success 个项目，$failed 个失败';
  @override
  String errorRestoringItemsWithError(String error) => '恢复项目时出错：$error';
  @override
  String errorDeletingItemsWithError(String error) => '删除项目时出错：$error';
  @override
  String errorDeletingFilesWithError(String error) => '删除文件时出错：$error';
  @override
  String errorOpeningRecycleBinWithError(String error) => '打开回收站时出错：$error';
  @override
  String get restoreSelected => '恢复所选项目';
  @override
  String get deleteSelected => '删除所选项目';
  @override
  String get selectItems => '选择项目';
  @override
  String get openRecycleBin => '打开回收站';
  @override
  String get emptyTrashTooltip => '清空回收站';
  @override
  String get trashIsEmpty => '回收站为空';
  @override
  String get itemsDeletedWillAppearHere => '您删除的项目会显示在这里';
  @override
  String originalLocation(String path) => '原始位置：$path';
  @override
  String deletedAt(String date, String size) => '删除时间：$date • $size';
  @override
  String get systemLabel => '系统';
  @override
  String errorLoadingTrashItemsWithError(String error) => '加载回收站项目时出错：$error';
  @override
  String get restoreTooltip => '恢复';
  @override
  String get deletePermanentlyTooltip => '永久删除';
  @override
  String get columnDateDeleted => '删除日期';
  @override
  String get columnOriginalPath => '原始路径';
  @override
  String get askCbAgentAboutThisFile => '向 CB Agent 询问此文件';
  @override
  String get askCbAgentAboutThisFolder => '向 CB Agent 询问此文件夹';

  // Misc helper labels
  @override
  String get networkFile => '网络文件';
  @override
  String tagCount(int count) => '$count 个标签';

  // Generic errors
  @override
  String errorGettingFolderProperties(String error) => '获取文件夹属性时出错：$error';
  @override
  String errorSavingTags(String error) => '保存标签时出错：$error';
  @override
  String errorCreatingFolder(String error) => '创建文件夹时出错：$error';
  @override
  String get pathNotAccessible => '路径不存在或无法访问';

  // UI labels
  @override
  String get noStorageLocationsFound => '未找到存储位置';
  @override
  String get driveGroupFixed => '此电脑';
  @override
  String get driveGroupRemovable => '可移动';
  @override
  String get driveGroupNetwork => '网络';
  @override
  String get driveGroupOther => '其他';
  @override
  String get driveTapToBrowse => '点击浏览';
  @override
  String get driveRestrictedAccess => '访问受限';
  @override
  String get driveEject => '弹出';
  @override
  String get driveEjectConfirmTitle => '弹出驱动器？';
  @override
  String driveEjectConfirmMessage(String name) => '要安全移除“$name”吗？请确保没有文件正在使用。';
  @override
  String get driveEjectSuccess => '驱动器已弹出';
  @override
  String driveEjectFailed(String error) => '无法弹出：$error';
  @override
  String get driveRename => '重命名';
  @override
  String get driveRenameTitle => '重命名卷';
  @override
  String get driveRenameHint => '卷标';
  @override
  String get driveRenameSuccess => '卷已重命名';
  @override
  String driveRenameFailed(String error) => '无法重命名：$error';
  @override
  String get driveFormatConfirmTitle => '格式化驱动器？';
  @override
  String driveFormatConfirmMessage(String name) =>
      '要为“$name”打开系统格式化工具吗？这可能会清除该卷上的所有数据。';
  @override
  String get driveOpenInCleaner => '在磁盘清理中打开';
  @override
  String get driveUsed => '已用';
  @override
  String get driveFree => '可用';
  @override
  String get driveTotal => '总计';
  @override
  String get driveType => '类型';
  @override
  String get driveFilesystem => '文件系统';
  @override
  String get driveSerial => '序列号';
  @override
  String get driveKindFixed => '本地磁盘';
  @override
  String get driveKindRemovable => '可移动';
  @override
  String get driveKindNetwork => '网络';
  @override
  String get driveKindOptical => '光驱';
  @override
  String get driveKindRam => 'RAM 磁盘';
  @override
  String get driveKindInternal => '内部存储';
  @override
  String get driveKindUnknown => '存储';
  @override
  String get openInNewPane => '在新窗格中打开';
  @override
  String get openInWindowsTerminal => '在 Windows 终端中打开';
  @override
  String get driveCleanup => '清理';
  @override
  String get driveFormat => '格式化';
  @override
  String get driveBitLocker => '启用 BitLocker';
  @override
  String get menuPinningOnlyLargeScreens => '仅大屏幕设备支持固定菜单';

  @override
  String get pinMenu => '固定菜单';

  @override
  String get unpinMenu => '取消固定菜单';

  @override
  String get pinnedSection => '已固定';
  @override
  String get favoritesSection => '个人收藏';
  @override
  String get sidebarApplications => '应用程序';
  @override
  String get sidebarDesktop => '桌面';
  @override
  String get sidebarPictures => '图片';
  @override
  String get sidebarMusic => '音乐';
  @override
  String get sidebarMovies => '影片';

  @override
  String get pinToSidebar => '固定到侧边栏';

  @override
  String get unpinFromSidebar => '从侧边栏取消固定';

  @override
  String get pinnedToSidebar => '已固定到侧边栏';

  @override
  String get removedFromSidebar => '已从侧边栏移除';

  @override
  String get exitApplicationTitle => '退出应用？';
  @override
  String moveToTrashConfirmMessage(String name) => '确定要将“$name”移到回收站吗？';
  @override
  String get exitApplicationConfirm => '确定要退出应用吗？';
  @override
  String itemsSelected(int count) => '已选择 $count 项';
  @override
  String itemsCount(int count) => '$count 个项目';
  @override
  String get noActiveTab => '没有活动的标签页';
  @override
  String get masonryLayoutName => '瀑布流布局 (Pinterest)';
  @override
  String get undo => '撤销';
  @override
  String errorWithMessage(String message) => '错误：$message';
  @override
  String get referencedFile => '引用的文件';
  @override
  String referencedFiles(int count) => '$count 个引用的文件';
  @override
  String pathsCopied(int count) => '已复制 $count 个路径';
  @override
  String get moveToTrashTitle => '移到回收站';
  @override
  String get imageMovedToTrash => '图片已移到回收站';
  @override
  String get failedToMoveImageToTrash => '无法将图片移到回收站';
  @override
  String failedToMoveImageToTrashWithError(String error) => '无法将图片移到回收站：$error';
  @override
  String get copiedPathToClipboard => '路径已复制到剪贴板';
  @override
  String get unableToOpenWithExternalApp => '无法使用外部应用打开';
  @override
  String failedToDisplayImageInformation(String error) => '无法显示图片信息：$error';
  @override
  String removedFromAlbum(int count) => '已从相册中移除 $count 张图片';
  @override
  String get addingFilesInBackground => '正在后台添加文件...';
  @override
  String addedFilesProgress(int added, int total) => '已添加 $added / $total 个文件';
  @override
  String get filesAddedSuccessfully => '文件添加成功';

  @override
  String get processing => '正在处理...';

  @override
  String get deletingFiles => '正在删除文件...';

  @override
  String get deletingItems => '正在删除项目...';

  @override
  String get movingItemsToTrash => '正在将项目移到回收站...';

  @override
  String get done => '完成';

  @override
  String get regenerateThumbnailsWithNewPosition => '按新位置重新生成缩略图';

  @override
  String get thumbnailPositionUpdated => '已清除缓存，将重新生成缩略图，位置：';

  @override
  String get fileTagsEnabled => '已启用文件标签显示';

  @override
  String get fileTagsDisabled => '已禁用文件标签显示';

  // System screen router
  @override
  String get unknownSystemPath => '未知的系统路径';

  @override
  String get ftpConnectionRequired => '需要 FTP 连接';

  @override
  String get ftpConnectionDescription => '您需要先连接到 FTP 服务器。';

  @override
  String get goToFtpConnections => '前往 FTP 连接';

  @override
  String get cannotOpenNetworkPath => '无法打开网络路径';

  @override
  String get goBack => '返回';

  @override
  String get tagPrefix => '标签';

  // Network browsing
  @override
  String get ftpConnections => 'FTP 连接';

  @override
  String get smbNetwork => 'SMB 网络';

  @override
  String get refreshData => '刷新';

  @override
  String get addConnection => '添加连接';

  @override
  String get noFtpConnections => '没有 FTP 连接。';

  @override
  String get activeConnections => '活动连接';

  @override
  String get savedConnections => '已保存的连接';

  @override
  String get connecting => '正在连接';

  @override
  String get connect => '连接';

  @override
  String get unknown => '未知';

  @override
  String get connectionError => '连接错误';

  @override
  String get loadCredentialsError => '加载已保存的凭据时出错';

  @override
  String get networkScanFailed => '网络扫描失败';

  @override
  String get smbVersionUnknown => '未知';

  @override
  String get connectionInfoUnavailable => '连接信息不可用';

  @override
  String get networkSettingsOpened => '已打开网络设置';

  @override
  String get cannotOpenNetworkSettings => '无法打开网络设置，请手动打开';

  @override
  String get networkDiscoveryDisabled => '网络发现可能未启用';

  @override
  String get networkDiscoveryDescription => '请在 Windows 设置中启用网络发现，以扫描 SMB 服务器';

  @override
  String get openSettings => '打开设置';

  @override
  String get activeConnectionsTitle => '活动连接';

  @override
  String get activeConnectionsDescription => '您已连接的 SMB 服务器';

  @override
  String get discoveredSmbServers => '发现的 SMB 服务器';

  @override
  String get discoveredSmbServersDescription => '在本地网络中发现的服务器';

  @override
  String get noActiveSmbConnections => '没有活动的 SMB 连接';

  @override
  String get connectToSmbServer => '连接到 SMB 服务器后会显示在这里';

  @override
  String get connected => '已连接';

  @override
  String get openConnection => '打开连接';

  @override
  String get disconnect => '断开连接';

  @override
  String get scanningForSmbServers => '正在扫描 SMB 服务器...';

  @override
  String get devicesWillAppear => '发现设备后会显示在这里';

  @override
  String get scanningMayTakeTime => '这可能需要一点时间';

  @override
  String get noSmbServersFound => '未找到 SMB 服务器';

  @override
  String get tryScanningAgain => '请重新扫描或检查您的网络设置';

  @override
  String get scanAgain => '重新扫描';

  @override
  String get readyToScan => '准备扫描';

  @override
  String get clickRefreshToScan => '点击刷新按钮开始扫描 SMB 服务器';

  @override
  String get startScan => '开始扫描';

  @override
  String get foundDevices => '已找到';

  @override
  String get scanning => '正在扫描...';

  @override
  String get scanComplete => '扫描完成';

  @override
  String get smbVersion => 'SMB 版本';

  @override
  String get netbios => 'NetBIOS';

  // Network - additional
  @override
  String get selectAll => '全选';
  @override
  String get unknownError => '发生未知错误。';
  @override
  String get networkConnections => '网络连接';
  @override
  String get availableServices => '可用服务';
  @override
  String get noActiveNetworkConnections => '没有活动的网络连接';
  @override
  String get useAddButtonToAddConnection => '使用 (+) 按钮添加新连接';
  @override
  String get unknownConnection => '未知连接';
  @override
  String serviceTypeConnection(String serviceName) => '$serviceName 连接';
  @override
  String get noServicesAvailable => '没有可用的服务';
  @override
  String get webdavConnections => 'WebDAV 连接';
  @override
  String errorOpeningTab(String tabName, String error) =>
      '打开 $tabName 的标签页时出错：$error';
  @override
  String connectToServiceServer(String serviceName) => '连接到 $serviceName 服务器';
  @override
  String get serviceType => '服务类型';
  @override
  String get host => '主机';
  @override
  String get deleteSavedConnection => '删除已保存的连接';
  @override
  String get username => '用户名';
  @override
  String get password => '密码';
  @override
  String get portOptional => '端口（可选）';
  @override
  String get useSslTls => '使用 SSL/TLS';
  @override
  String get basePathOptional => '基础路径（可选）';
  @override
  String get basePathHint => '例如 /webdav';
  @override
  String get domainOptional => '域（可选）';
  @override
  String get saveCredentials => '保存凭据';
  @override
  String get saveCredentialsDescription => '保存登录信息，以便下次连接使用';
  @override
  String get deleteSavedConnectionTitle => '删除已保存的连接？';
  @override
  String deleteSavedConnectionConfirm(String host) => '确定要删除“$host”的已保存连接吗？';
  @override
  String connectionDeleted(String host) => '“$host”的连接已删除。';
  @override
  String connectionNotFoundToDelete(String host) => '找不到要删除的“$host”连接。';
  @override
  String get errorDeletingConnection => '删除连接时出错';
  @override
  String connectionFailed(String error) => '连接失败：$error';
  @override
  String get networkConnection => '网络连接';
  @override
  String get notConnected => '未连接';
  @override
  String get refreshSmbVersionInfo => '刷新 SMB 版本信息';
  @override
  String shareLabel(String sharePath) => '共享：$sharePath';
  @override
  String get rootShare => '根共享';
  @override
  String foundDevicesCount(int count) => '找到 $count 台设备';
  @override
  String get noWebdavConnections => '没有 WebDAV 连接。';
  @override
  String get addConnectionOrSampleToStart => '添加新连接或示例即可开始。';
  @override
  String get addSample => '添加示例';
  @override
  String get editWebdavConnection => '编辑 WebDAV 连接';
  @override
  String get update => '更新';
  @override
  String get connectionUpdatedSuccess => '连接更新成功';
  @override
  String get failedToUpdateConnection => '更新连接失败';
  @override
  String get deleteConnection => '删除连接';
  @override
  String deleteConnectionConfirm(String host) => '确定要删除与“$host”的连接吗？';
  @override
  String get connectionDeletedSuccess => '连接删除成功';
  @override
  String get failedToDeleteConnection => '删除连接失败';
  @override
  String get addSampleWebdavConnection => '添加示例 WebDAV 连接';
  @override
  String get sampleConnectionAddedSuccess => '示例连接添加成功';
  @override
  String get failedToAddSampleConnection => '添加示例连接失败';
  @override
  String lastConnected(String dateStr) => '上次连接：$dateStr';
  @override
  String get editConnection => '编辑连接';
  @override
  String get closeConnection => '关闭连接';
  @override
  String get retry => '重试';
  @override
  String get networkErrorPersistsHint => '如果此错误持续出现，请检查您的网络连接和服务器状态。';
  @override
  String get pleaseEnterHost => '请输入主机';
  @override
  String get pleaseEnterPort => '请输入端口';
  @override
  String get pleaseEnterValidPort => '请输入有效的端口号';
  @override
  String get connectionMode => '连接模式：';
  @override
  String get passive => '被动';
  @override
  String get active => '主动';
  @override
  String get port => '端口';
  @override
  String get basePath => '基础路径';

  // Drawer menu items
  @override
  String get networksMenu => '网络';

  @override
  String get networkTab => '网络';

  @override
  String get about => '关于';

  // Tab manager
  @override
  String get newTabButton => '新建标签页';

  @override
  String get openNewTabToStart => '打开新标签页即可开始';

  @override
  String get tabManager => '标签页管理器';

  @override
  String get openTabs => '已打开的标签页';

  @override
  String get noTabsOpen => '没有打开的标签页';

  @override
  String get closeAllTabs => '关闭所有标签页';

  @override
  String get activeTab => '活动';

  @override
  String get closeTab => '关闭标签页';

  @override
  String get closeOtherTabs => '关闭其他标签页';

  @override
  String get markTabInactive => '标记为不活动';

  @override
  String get restoringTab => '正在恢复标签页…';

  @override
  String get keepTabAlwaysActive => '让标签页始终保持活动';

  @override
  String get allowTabAutoSuspend => '允许标签页自动挂起';

  @override
  String get tabAlwaysActiveTooltip => '始终活动';

  @override
  String get addNewTab => '添加新标签页';

  // Desktop windows (tabbed browsing)
  @override
  String get newWindow => '新建窗口';

  @override
  String get moveTabToNewWindow => '将标签页移到新窗口';

  @override
  String get moveTabToWindow => '将标签页移到窗口...';

  @override
  String get mergeWindowIntoThis => '将窗口合并到此处...';

  @override
  String get selectWindow => '选择窗口';

  @override
  String get noOtherWindows => '没有其他窗口';

  // Home screen
  @override
  String get welcomeTitle => '欢迎使用 CB File Hub';

  @override
  String get welcomeSubtitle => '您强大的文件管理助手';

  @override
  String get quickActionsTip => '提示：使用下方的快捷操作可快速上手';

  @override
  String get quickActionsHome => '快捷操作';

  @override
  String get startHere => '从这里开始';

  @override
  String get newTabAction => '新建标签页';

  @override
  String get newTabActionDesc => '打开新的文件浏览器标签页';

  @override
  String get tagsAction => '标签';

  @override
  String get tagsActionDesc => '使用智能标签整理';

  @override
  String get imageGalleryTab => '图片库';

  @override
  String get videoGalleryTab => '视频库';

  @override
  String get drivesTab => '驱动器';

  @override
  String get browseTab => '浏览';

  @override
  String get documentsTab => '文档';

  @override
  String get homeTab => '主页';

  @override
  String get internalStorage => '内部存储';

  @override
  String get storagePrefix => '存储';

  @override
  String get rootFolder => '根目录';

  // Video Hub
  @override
  String get videoHub => '视频中心';

  @override
  String get manageYourVideos => '管理您的视频';

  @override
  String get videos => '视频';

  @override
  String get videoActions => '视频操作';

  @override
  String get allVideos => '所有视频';

  @override
  String get browseAllYourVideos => '浏览您的所有视频';

  @override
  String get videosFolder => '视频文件夹';

  @override
  String get openFileManager => '打开文件管理器';
  @override
  String get videoStatistics => '视频统计';

  @override
  String get totalVideos => '视频总数';

  // Gallery Hub
  @override
  String get galleryHub => '图库中心';

  @override
  String get managePhotosAndAlbums => '管理您的照片和相册';

  @override
  String get images => '图片';

  @override
  String get galleryActions => '图库操作';

  @override
  String get quickAccess => '快速访问';

  @override
  String get thisPC => '此电脑';

  @override
  String get browseAllYourPictures => '浏览您的所有图片';

  @override
  String get browseAllYourPhotos => '浏览您的所有照片';

  @override
  String get organizeInAlbums => '用相册整理';

  @override
  String get picturesFolder => '图片文件夹';

  @override
  String get photosFromCamera => '相机拍摄的照片';

  @override
  String get downloadedFiles => '已下载的文件';

  @override
  String get downloadedImages => '已下载的图片';

  @override
  String get featuredAlbums => '精选相册';

  @override
  String get personalized => '个性化';

  @override
  String get configureFeaturedAlbums => '配置精选相册';

  @override
  String get noFeaturedAlbums => '没有精选相册';

  @override
  String get createSomeAlbumsToSeeThemFeaturedHere => '创建一些相册，即可在这里看到精选内容';

  @override
  String get removeFromFeatured => '从精选中移除';

  @override
  String get galleryStatistics => '图库统计';

  @override
  String get totalImages => '图片总数';

  @override
  String get albums => '相册';

  @override
  String get allImages => '所有图片';

  @override
  String get camera => '相机';

  @override
  String get downloads => '下载';

  @override
  String get recent => '最近';

  @override
  String get folders => '文件夹';

  // Video player playlist
  @override
  String get videoPlaylist => '播放列表';

  // Video player screenshot
  @override
  String get takeScreenshot => '截图';

  @override
  String get screenshotSaved => '截图已保存';

  @override
  String get screenshotSavedAt => '截图已保存到';

  @override
  String get screenshotFailed => '保存截图失败';

  @override
  String get screenshotSavedToFolder => '截图已保存到“截图”文件夹';

  @override
  String get openScreenshotFolder => '打开文件夹';

  @override
  String get viewScreenshot => '查看';

  @override
  String get screenshotNotAvailable => '无法截图';

  @override
  String get screenshotNotAvailableMessage => '无法捕获此画面。请等待视频加载完成后重试。';

  @override
  String get screenshotFileNotFound => '未找到图片文件';

  @override
  String get screenshotCannotOpenTab => '在当前环境下无法打开文件夹标签页';

  @override
  String get screenshotErrorOpeningFolder => '打开文件夹时出错';

  @override
  String get closeAction => '关闭';

  @override
  String get pipOverlayEnabled => '画中画浮层已启用';

  @override
  String get pipAndroidEnableFailed => '无法在 Android 上启用画中画';

  @override
  String pipError(String error) => '画中画错误：$error';

  @override
  String get pipNoSource => '没有可用于打开画中画的视频源';

  @override
  String get pipOpenedInSeparateWindow => '画中画已在单独的窗口中打开';

  @override
  String get pipNotSupportedOnPlatform => '此平台不支持画中画';

  // Video library
  @override
  String get videoLibrary => '视频库';

  @override
  String get videoLibraries => '视频库';

  @override
  String get createVideoLibrary => '创建视频库';

  @override
  String get editVideoLibrary => '编辑视频库';

  @override
  String get deleteVideoLibrary => '删除视频库';

  @override
  String get addVideoSource => '添加视频来源';

  @override
  String get removeVideoSource => '移除来源';

  @override
  String get videoSources => '视频来源';

  @override
  String get noVideoSources => '尚未添加视频来源';

  @override
  String get createImageSource => '创建图片来源';

  @override
  String get editImageSource => '编辑图片来源';

  @override
  String get addImageSource => '添加图片来源';

  @override
  String get removeImageSource => '移除来源';

  @override
  String get imageSources => '图片来源';

  @override
  String get noImageSources => '尚未添加图片来源';

  @override
  String get filterByTags => '按标签筛选';

  @override
  String get clearTagFilter => '清除筛选';

  @override
  String get recentVideos => '最近的视频';

  @override
  String get videoHubTitle => '视频中心';

  @override
  String get videoHubWelcome => '管理您的视频库';

  @override
  String get manageVideoLibraries => '管理视频库';

  @override
  String get videoCount => '视频数量';

  @override
  String get scanForVideos => '扫描视频';

  @override
  String get rescanLibrary => '重新扫描视频库';

  @override
  String deleteVideoLibraryConfirmation(String name) => '删除视频库“$name”？';

  @override
  String get libraryDeletedSuccessfully => '视频库已成功删除';

  @override
  String get sourceAdded => '来源添加成功';

  @override
  String get sourceRemoved => '来源移除成功';

  @override
  String get selectVideoSource => '选择视频来源文件夹';

  @override
  String get videoLibrarySettings => '视频库设置';

  @override
  String get manageVideoSources => '管理视频来源';

  @override
  String get videoExtensions => '视频扩展名';

  @override
  String get includeSubdirectories => '包含子目录';

  @override
  String get noVideosInLibrary => '此视频库中没有视频';

  @override
  String get libraryCreatedSuccessfully => '视频库创建成功';

  @override
  String videoLibraryCount(int count) => '$count 个视频库';

  @override
  String get libraryCover => '视频库封面';

  @override
  String get changeCoverImage => '更换封面';

  @override
  String get removeCoverImage => '移除封面';

  @override
  String get coverImageUpdated => '封面图片已更新';

  @override
  String get coverImageRemoved => '封面图片已移除';

  @override
  String get coverImageUpdateFailed => '更新封面图片失败';

  @override
  String get lastScanLabel => '上次扫描';

  @override
  String get neverScanned => '从未扫描';

  // Streaming and download dialogs
  @override
  String openFileTypeFile(String fileType) => '打开 $fileType 文件';
  @override
  String streamDownloadPrompt(String fileType) =>
      '$fileType 文件类型不支持直接流式播放。要将其下载到您的设备吗？';
  @override
  String get downloadingFile => '正在下载文件...';
  @override
  String get fileDownloadedSuccess => '文件下载成功';
  @override
  String get errorDownloadingFile => '下载文件时出错';
  @override
  String get errorTitle => '错误';
  @override
  String get mediaPlaybackError => '媒体播放错误';
  @override
  String mediaPlaybackErrorSmbContent(String error) =>
      '无法播放此 SMB 文件：\n\n$error\n\n请检查：\n• SMB 连接\n• 文件路径\n• 文件访问权限';
  @override
  String mediaPlaybackErrorNativeContent(String error) =>
      '无法播放此 SMB 文件：\n\n$error\n\n请检查：\n• SMB 连接\n• 文件路径\n• 文件访问权限\n• 原生 SMB 客户端是否可用';
  @override
  String get chooseAnotherApp => '选择其他应用...';
  @override
  String get folderProperties => '文件夹属性';
  @override
  String get createNewFolder => '新建文件夹';
  @override
  String get createNewFile => '新建文件';
  @override
  String get folderPropertyPath => '路径';
  @override
  String get folderPropertyCreated => '创建时间';
  @override
  String get folderPropertyContent => '内容';
  @override
  String get folderPropertySizeDirectChildren => '大小（直接子项）';
  @override
  String get networkServiceNotAvailable => '网络服务不可用';
  @override
  String get folderNameLabel => '文件夹名称';
  @override
  String get fileNameLabel => '文件名';
  @override
  String errorCreatingFile(String error) => '创建文件时出错：$error';
  @override
  String get noFileSelectedForBenchmarking => '未选择用于基准测试的文件';
  @override
  String benchmarkError(String error) => '基准测试错误：$error';
  @override
  String benchmarkFailed(String error) => '基准测试失败：$error';
  @override
  String get saveTagToLocalDatabaseFailed => '无法将标签保存到本地数据库';
  @override
  String saveTagFailed(String error) => '保存标签失败：$error';
  @override
  String debugTagsSeeded(int savedCount, int requestedCount) =>
      '已成功生成 $savedCount/$requestedCount 个标签';
  @override
  String debugTagsSeedFailed(String error) => '生成标签时出错：$error';
  @override
  String get debugTagsCleared => '所有标签已清除';
  @override
  String debugTagsClearFailed(String error) => '清除标签时出错：$error';
  @override
  String addFolderToAlbumFailed(String error) => '添加文件夹时出错：$error';
  @override
  String addFilesToAlbumFailed(String error) => '添加文件时出错：$error';
  @override
  String loadRulesFailed(String error) => '加载规则时出错：$error';
  @override
  String openTerminalFailed(String error) => '无法打开终端：$error';
  @override
  String startCleanupFailed(String error) => '无法开始清理：$error';
  @override
  String startFormatFailed(String error) => '无法开始格式化：$error';
  @override
  String foundResultsWithTag(int count, String tag) =>
      '找到 $count 个带有标签“$tag”的结果';

  // AI Agent
  @override
  String get aiSearchAgent => 'AI 搜索助手';
  @override
  String get aiSearchAgentDescription => '配置 AI 提供商，实现智能文件搜索';
  @override
  String get aiProvider => 'AI 提供商';
  @override
  String get aiProviders => 'AI 提供商';
  @override
  String get addProvider => '添加提供商';
  @override
  String get editProvider => '编辑提供商';
  @override
  String get deleteProvider => '删除提供商';
  @override
  String get providerPreset => '提供商预设';
  @override
  String get selectProviderPreset => '选择提供商预设';
  @override
  String get providerName => '提供商名称';
  @override
  String get apiType => 'API 类型';
  @override
  String get authMode => '身份验证';
  @override
  String get defaultModel => '默认模型';
  @override
  String get apiKey => 'API 密钥';
  @override
  String get codexOauth => 'Codex OAuth';
  @override
  String get endpointUrl => '端点网址';
  @override
  String get modelName => '模型名称';
  @override
  String get openAiCompatible => '兼容 OpenAI';
  @override
  String get anthropic => 'Anthropic';
  @override
  String get temperature => '温度';
  @override
  String get maxTokens => '最大 Token 数';
  @override
  String get systemPrompt => '系统提示词';
  @override
  String get timeout => '超时（秒）';
  @override
  String get maxRetries => '最大重试次数';
  @override
  String get testConnection => '测试连接';
  @override
  String get connectionSuccess => '连接成功';
  @override
  String get aiConnectionFailed => '连接失败';
  @override
  String get enableAiSearch => '启用 AI 搜索';
  @override
  String get defaultSearchScope => '默认搜索范围';
  @override
  String get maxContentReadSize => '最大内容读取大小';
  @override
  String get providerEnabled => '提供商已启用';
  @override
  String get providerDisabled => '提供商已禁用';
  @override
  String get providerPriority => '优先级';
  @override
  String get advancedSettings => '高级设置';
  @override
  String get testingConnection => '正在测试连接...';
  @override
  String get codexOauthDescription => '使用本地的 Codex/ChatGPT 登录，而不是原始 API 密钥。';
  @override
  String get codexCredentialUnavailable => '此设备上没有可用的 Codex 凭据路径。';
  @override
  String get codexCredentialMissing => '未找到 Codex OAuth 凭据。请先运行 codex login。';
  @override
  String get launchCodexLogin => '启动 Codex 登录';
  @override
  String get codexLoginLaunched => 'Codex 登录已在单独的终端窗口中启动。';
  @override
  String get checkCredentials => '检查凭据';
  @override
  String deleteProviderConfirmation(String name) => '确定要删除提供商“$name”吗？';
  @override
  String get noProviders => '尚未配置 AI 提供商';

  // AI Chat
  @override
  String get aiChat => 'AI 聊天';
  @override
  String get askAiToFindFiles => '让 AI 帮您查找文件...';
  @override
  String get sendMessage => '发送';
  @override
  String get clearChat => '清除聊天';
  @override
  String get searchScope => '搜索范围';
  @override
  String get currentFolder => '当前文件夹';
  @override
  String get recursiveSearch => '递归搜索';
  @override
  String get aiTaggedFiles => '已加标签的文件';
  @override
  String get allDrives => '所有驱动器';
  @override
  String get findingFiles => '正在查找文件...';
  @override
  String get noResultsFound => '未找到结果';
  @override
  String get aiSearchResults => 'AI 搜索结果';
  @override
  String get retryMessage => '重试';
  @override
  String get providerFallback => '正在尝试下一个提供商...';
  @override
  String get allProvidersFailed => '所有 AI 提供商均失败';
  @override
  String get setupAiProvider => '请在“设置”中配置 AI 提供商';
  @override
  String get noProviderConfigured => '未配置 AI 提供商';
  @override
  String get relevanceScore => '相关度';
  @override
  String get aiExplanation => 'AI 说明';
  @override
  String get aiSearchMode => 'AI 搜索';
  @override
  String get switchToAiSearch => '切换到 AI 搜索';
  @override
  String get switchToNormalSearch => '切换到普通搜索';
  @override
  String get aiChatTab => 'AI 聊天';
  @override
  String get suggestRecentPhotos => '查找最近的照片';
  @override
  String get suggestLargeVideos => '显示大视频';
  @override
  String get suggestTaggedFiles => '标记为…的文件';
  @override
  String get fetchModels => '获取模型';
  @override
  String get fetchingModels => '正在获取模型...';
  @override
  String get loadingModels => '正在加载模型...';
  @override
  String get noModelsFound => '未找到模型';
  @override
  String get noModelConfigured => '无模型';
  @override
  String get selectModel => '选择模型';
  @override
  String get modelSearchHint => '搜索模型...';
  @override
  String fetchModelsError(String error) => '获取模型失败：$error';
  @override
  String get newConversation => '新建聊天';
  @override
  String get conversations => '对话';
  @override
  String get deleteConversation => '删除对话';
  @override
  String get noConversations => '还没有对话';

  // CB Agent rebrand
  @override
  String get cbAgent => 'CB Agent';
  @override
  String get cbAgentTitle => 'CB Agent';
  @override
  String get cbAgentSubtitle => 'CB File Hub 内置 AI 助手';

  // Disk Cleaner (CB Agent skill)
  @override
  String get cbAgentCleanerTitle => '磁盘清理 (CB Agent)';
  @override
  String get diskCleanerNotAvailable => '磁盘清理仅在 Windows 上可用';
  @override
  String get diskCleanerScanTitle => '扫描垃圾文件';
  @override
  String get diskCleanerScanRunning => '正在扫描...';
  @override
  String get diskCleanerScanDone => '扫描完成';
  @override
  String get diskCleanerCleanTitle => '清理垃圾文件';
  @override
  String get diskCleanerCleanDone => '清理完成';
  @override
  String get diskCleanerAskAgent => '询问 CB Agent';

  @override
  String get diskCleanerSuggestAndSelect => '快速分析';
  @override
  String get diskCleanerAdviceFromScan => '基于扫描元数据';
  @override
  String get diskCleanerAdviceFromAi => 'AI 建议';

  @override
  String get diskCleanerAiSelectRecommendationsRequest =>
      '请根据扫描元数据快速概述：这些数据是什么，以及应保留还是可以考虑删除。'
      '对每个分组给出简短说明；仅用 AI 分析少数不明确的分组。'
      '不要读取文件内容，不要选择文件，也不要删除任何内容。请用中文回答。';
  @override
  String get diskCleanerAgentAnalysisTitle => 'CB Agent 分析';
  @override
  String diskCleanerAgentGroupCount(int count) => '共同评估了 $count 个条目';
  @override
  String get diskCleanerAgentInspecting => 'CB Agent 正在检查此项目';
  @override
  String get diskCleanerAgentCanClean => '可清理';
  @override
  String get diskCleanerAgentNeedsReview => '请先查看';
  @override
  String get diskCleanerAgentKeep => '保留';
  @override
  String get diskCleanerAiInspectItemRequest =>
      '先读取 get_current_cleaner_scan，然后使用 '
      'inspect_cleaner_scan_item 检查这个确切的路径，并使用 '
      'set_cleaner_scan_item_analysis（select:false）在扫描界面上显示您的评估。'
      '说明应该清理、查看还是保留。请用中文回答。';
  @override
  String get diskCleanerMoveToRecycleBin => '移到回收站';
  @override
  String get diskCleanerPermanentDelete => '永久删除';
  @override
  String get diskCleanerSelectCategories => '选择类别';
  @override
  String get diskCleanerSelectDrives => '选择驱动器';
  @override
  String get diskCleanerScanAgain => '重新扫描';
  @override
  String get diskCleanerCachedResultStatus => '正在显示上次的扫描结果（缓存）。重新扫描以刷新。';

  // Disk Cleaner — extended UI strings
  @override
  String get diskCleanerCancel => '取消';
  @override
  String get diskCleanerShowCleanableOnly => '仅显示可清理项';
  @override
  String diskCleanerCleanableOnlyChip(int count) => '仅可清理项 ($count)';
  @override
  String get diskCleanerCheckAllCleanable => '勾选所有可清理项';
  @override
  String get diskCleanerUncheckAll => '取消全部勾选';

  @override
  String get diskCleanerColumnName => '名称';
  @override
  String get diskCleanerColumnSize => '大小';
  @override
  String get diskCleanerColumnPercentOfParent => '占上级比例';
  @override
  String get diskCleanerColumnFiles => '文件';
  @override
  String get diskCleanerBuildingTree => '正在构建磁盘树...';
  @override
  String get diskCleanerNoFilesFound => '未找到文件';
  @override
  String get diskCleanerAnalyzingDisk => '正在分析磁盘使用情况...';
  @override
  String get diskCleanerPieChartPending => '扫描完成后将显示饼图。';
  @override
  String get diskCleanerPieEmpty => '空';
  @override
  String get diskCleanerPreparingFiles => '正在准备文件...';
  @override
  String get diskCleanerCleaning => '正在清理...';
  @override
  String get diskCleanerScanningSelectedDirs => '正在扫描所选目录...';
  @override
  String get diskCleanerDeletingJunkHint => '正在删除所选项目。如果某个文件删除失败，您可以跳过或重试。';
  @override
  String get diskCleanerPermanentDeleteLabel => '永久删除';
  @override
  String get diskCleanerRecycleBinLabel => '回收站';
  @override
  String get diskCleanerDeletingItems => '正在删除项目...';
  @override
  String get diskCleanerReviewMode => '审阅模式';
  @override
  String get diskCleanerBackToResults => '返回结果';
  @override
  String get diskCleanerReviewByAgent => '由 CB Agent 审阅';
  @override
  String get diskCleanerPermanentlyDeleting => '正在永久删除...';
  @override
  String get diskCleanerMovingToRecycleBin => '正在移到回收站...';
  @override
  String get diskCleanerWaitingDecision => '正在等待您的决定...';
  @override
  String get diskCleanerFileInUse => '此文件似乎正被其他应用程序使用。';
  @override
  String get diskCleanerRetryInUseHint => '在使用此文件的应用或进程关闭之前，重试通常仍会失败。';
  @override
  String get diskCleanerBlockedBy => '被以下程序占用：';
  @override
  String get diskCleanerSkipAllRemaining => '跳过所有剩余项目';
  @override
  String get diskCleanerSkip => '跳过';
  @override
  String get diskCleanerTryAgain => '重试';
  @override
  String get diskCleanerPermanentDeleteConfirmTitle => '永久删除？';
  @override
  String diskCleanerPermanentDeleteFromBinContent(int count, String size) =>
      '这将从回收站中永久删除 $count 个项目（$size）。删除后无法恢复。';
  @override
  String diskCleanerPermanentDeleteSelectedContent(int count, String size) =>
      '这将永久删除所选的 $count 个项目（$size）。删除后无法恢复。';
  @override
  String get diskCleanerColumnFileName => '文件名';
  @override
  String get diskCleanerColumnPath => '路径';
  @override
  String get diskCleanerColumnCategory => '类别';
  @override
  String get diskCleanerRecycleBinEmpty => '回收站中当前没有项目。';
  @override
  String diskCleanerItemsInRecycleBin(int count, String size) =>
      '回收站中有 $count 个项目（$size）';
  @override
  String diskCleanerSkippedInUseSnack(int count) =>
      '已跳过 $count 个正在使用的文件。详情已记录。';
  @override
  String diskCleanerSkippedAfterFailureSnack(int count) =>
      '删除失败后已跳过 $count 个文件。';
  @override
  String diskCleanerFreedBadge(String size, int count) =>
      '已释放 $size  •  $count 个项目';
  @override
  String diskCleanerFailedBadge(int count) => '$count 个失败';
  @override
  String diskCleanerInUseBadge(int count) => '$count 个正在使用';
  @override
  String diskCleanerSkippedBadge(int count) => '已跳过 $count 个';
  @override
  String diskCleanerSkippedInUseBanner(int count) =>
      '已跳过 $count 个正在使用的文件。完整路径列表请查看日志。';
  @override
  String diskCleanerSkippedByUserBanner(int count) =>
      '您选择了“跳过”，因此删除失败后已跳过 $count 个文件。';
  @override
  String diskCleanerDeletedPermanentlyBody(int count) => '已永久删除 $count 个项目。';
  @override
  String diskCleanerFreedSpace(String size) => '已释放 $size';
  @override
  String diskCleanerPermanentDeleteFinished(int count) =>
      '已完成 $count 个项目的永久删除。';
  @override
  String diskCleanerPermanentDeletingProgress(int done, int total) =>
      '正在永久删除... $done / $total';
  @override
  String get diskCleanerDeletingLabel => '正在删除...';
  @override
  String get diskCleanerRemaining => '剩余';
  @override
  String diskCleanerDriveFree(String label, String size) => '$label  可用 $size';
  @override
  String diskCleanerFilesCount(int count) => '$count 个文件';
  @override
  String diskCleanerDirsCount(int count) => '$count 个目录';
  @override
  String get diskCleanerStarting => '正在启动...';
  @override
  String diskCleanerDriveSummary(String path, String size, int count) =>
      '$path  $size  •  $count 个文件';
  @override
  String get diskCleanerGrowthTitle => '最近增长的文件夹';
  @override
  String diskCleanerGrowthFilter(int count) => '最近增长 ($count)';
  @override
  String diskCleanerGrowthIncrease(String size) => '+$size';
  @override
  String diskCleanerGrowthCurrentSize(String size) => '当前大小：$size';
  @override
  String diskCleanerAgentPath(String path) => 'CB Agent：$path';
  @override
  String diskCleanerItemsBytes(int count, String size) => '$count 个项目 • $size';
  @override
  String diskCleanerSizeFiles(String size, int files) => '$size • $files 个文件';

  @override
  String diskCleanerRolledUpItems(int items) => '$items 个较小的项目';
  @override
  String diskCleanerScannedProgress(String size, int files) =>
      '已扫描 $size • $files 个文件';
  @override
  String get diskCleanerPieChartPendingScan => '扫描完成后将立即显示饼图';
  @override
  String get diskCleanerIncrementalScanTitle => '增量扫描';
  @override
  String diskCleanerIncrementalScanProgress(int count) => '已更新 $count 个有变化的文件夹';
  @override
  String get diskCleanerFullScanFallback => '增量扫描不可用 — 已完成完整扫描';
  @override
  String get diskCleanerOldLargeTitle => '旧的大型项目';
  @override
  String get diskCleanerOldLargeSubtitle => '仅供审阅提示。文件系统时间戳并不能证明项目未被使用。';
  @override
  String get diskCleanerOldLargeAll => '全部';
  @override
  String get diskCleanerOldLargeFiles => '文件';
  @override
  String get diskCleanerOldLargeFolders => '文件夹';
  @override
  String diskCleanerOldLargeLastActivity(String date) => '最近活动提示：$date';
  @override
  String get diskCleanerOldLargeReviewOnly => '仅供审阅';
  @override
  String get diskCleanerOldLargeEmpty => '未找到旧的大型文件或文件夹。';
  @override
  String diskCleanerScanningPath(String path) => '正在扫描 $path';
  @override
  String diskCleanerProcessedCount(int done, int total) => '已处理 $done / $total';
  @override
  String diskCleanerJunkSummary(String size) => '垃圾文件：$size';
  @override
  String get diskCleanerContinue => '继续';
  @override
  String get diskCleanerAiPanelUnavailable => 'AI 面板在当前环境下不可用';
  @override
  String get diskCleanerAskAgentAboutThis => '就此向 CB Agent 提问';
  @override
  String get diskCleanerAiDeleteAnalysisIntro => '请分析我是否应该删除这个文件或文件夹：';
  @override
  String get diskCleanerAiLabelPath => '路径';
  @override
  String get diskCleanerAiLabelType => '类型';
  @override
  String get diskCleanerAiLabelName => '名称';
  @override
  String get diskCleanerAiLabelSize => '大小';
  @override
  String get diskCleanerAiLabelFiles => '文件';
  @override
  String get diskCleanerAiTypeFile => '文件';
  @override
  String get diskCleanerAiTypeFolder => '文件夹';
  @override
  String diskCleanerAiCategoryMarkedJunk(String category) =>
      '类别：$category（已标记为垃圾）';
  @override
  String get diskCleanerAiNotMarkedAsJunk => '规则未将其标记为垃圾。';
  @override
  String get diskCleanerAiDeleteAnalysisQuestion =>
      '请说明这个文件或文件夹可能用于什么、是否可以安全删除、我需要考虑哪些风险，并给出明确的建议：删除、保留或手动检查。请用中文回答。';
  @override
  String diskCleanerScanFailedMsg(String error) => '扫描失败：$error';
  @override
  String diskCleanerCleanupFailedMsg(String error) => '清理失败：$error';
  @override
  String diskCleanerPermanentDeleteFailedMsg(String error) => '永久删除失败：$error';
  @override
  String diskCleanerAgentFoundJunk(int count, String size) =>
      'CB Agent 发现了 $count 个垃圾项目（$size）';
  @override
  String diskCleanerAndMoreItems(int count) => '... 以及另外 $count 个项目';
  @override
  String diskCleanerSelectedBytes(String size, String total) =>
      '已选择：$size / $total';
  @override
  String diskCleanerReviewModeSelected(String size) => '审阅模式 • 已选择：$size';
  @override
  String diskCleanerDeletePermanentlyButton(String size) => '永久删除 $size';
  @override
  String diskCleanerMoveToRecycleBinButton(String size) => '将 $size 移到回收站';
  @override
  String diskCleanerReviewAndClean(String size) => '查看并清理 $size';
  @override
  String diskCleanerPermanentDeletedSuccess(int count, String size) =>
      '已永久删除 $count 个项目（$size）';
  @override
  String diskCleanerPermanentDeletedWithInUse(
    int count,
    String size,
    int skipped,
  ) => '已永久删除 $count 个项目（$size）。已跳过 $skipped 个正在使用的文件，详情已记录。';
  @override
  String diskCleanerPermanentDeletedWithSkipped(
    int count,
    String size,
    int skipped,
  ) => '已永久删除 $count 个项目（$size）。删除失败后已跳过 $skipped 个文件。';

  // Cleaner - drive picker, quick clean, junk reasons
  @override
  String get diskCleanerDriveLowSpace => '空间不足';
  @override
  String diskCleanerDriveCapacity(String used, String total, String free) =>
      '已用 $used / 共 $total · 可用 $free';
  @override
  String diskCleanerLastScanFound(String when, String junk) =>
      '上次扫描：$when · 发现 $junk 垃圾文件';
  @override
  String get diskCleanerTimeJustNow => '刚刚';
  @override
  String get diskCleanerTimeToday => '今天';
  @override
  String get diskCleanerTimeYesterday => '昨天';
  @override
  String diskCleanerTimeDaysAgo(int days) => '$days 天前';
  @override
  String diskCleanerTimeWeeksAgo(int weeks) => '$weeks 周前';
  @override
  String diskCleanerTimeMonthsAgo(int months) =>
      months <= 1 ? '1 个月前' : '$months 个月前';
  @override
  String get diskCleanerQuickCleanHint => '临时文件、缓存和回收站。应用会在需要时重新生成这些内容。';
  @override
  String get diskCleanerQuickCleanButton => '快速清理';
  @override
  String get diskCleanerQuickCleanScanning => '正在查找安全的项目...';
  @override
  String get diskCleanerQuickCleanNothing => '目前没有可安全清理的内容';
  @override
  String get diskCleanerQuickCleanReviewTitle => '查看快速清理';
  @override
  String diskCleanerQuickCleanReviewSubtitle(int count, String size) =>
      '这些分组中共有 $count 个项目，合计 $size。';
  @override
  String get diskCleanerQuickCleanRecycleNote => '所有内容都会移到回收站，您可以从那里恢复。';
  @override
  String get diskCleanerCategoryWindowsTemp => 'Windows 临时文件';
  @override
  String get diskCleanerCategoryBrowserCache => '浏览器缓存';
  @override
  String get diskCleanerCategoryRecycleBin => '回收站';
  @override
  String get diskCleanerCategoryThumbnailCache => '缩略图缓存';
  @override
  String get diskCleanerCategoryAppCache => '应用缓存';
  @override
  String get diskCleanerCategoryCrashLogs => '崩溃转储和日志';
  @override
  String get diskCleanerCategoryWindowsUpdate => 'Windows 更新缓存';
  @override
  String get diskCleanerCategoryPrefetch => '预读取数据';
  @override
  String get diskCleanerCategoryDeliveryOptimization => '传递优化文件';
  @override
  String get diskCleanerCategoryDevCache => '开发者缓存';
  @override
  String get diskCleanerReasonWindowsTemp => '由应用遗留下来的文件。可以安全删除，没有任何程序依赖它们。';
  @override
  String get diskCleanerReasonBrowserCache => '浏览器会在需要时重新生成。网页可能会有一次稍慢的加载。';
  @override
  String get diskCleanerReasonRecycleBin => '已经删除、等待清空的文件。';
  @override
  String get diskCleanerReasonThumbnailCache => 'Windows 会在您下次打开文件夹时重新生成缩略图。';
  @override
  String get diskCleanerReasonAppCache => '应用的临时数据。应用会重新创建，您不会退出登录。';
  @override
  String get diskCleanerReasonCrashLogs => '过去崩溃留下的诊断文件。仅对排查问题有用。';
  @override
  String get diskCleanerReasonWindowsUpdate => '已经应用的更新的安装程序。';
  @override
  String get diskCleanerReasonPrefetch => '应用启动提示。Windows 会在接下来的几次启动中重新生成。';
  @override
  String get diskCleanerReasonDeliveryOptimization => '为与网络中其他电脑共享而缓存的更新文件。';
  @override
  String get diskCleanerReasonDevCache => '构建和软件包缓存。您的工具会重新下载或重新构建。';
  @override
  String get diskCleanerReasonGeneric => '匹配已知的垃圾文件位置，可以安全删除。';

  // Cleaner - tree preset views
  @override
  String get diskCleanerPresetTooltip => '筛选目录树';
  @override
  String get diskCleanerPresetAll => '全部';
  @override
  String get diskCleanerPresetLargeFiles => '超过 1 GB 的文件';
  @override
  String get diskCleanerPresetLogsCaches => '日志和缓存';
  @override
  String get diskCleanerPresetInstallers => '安装程序和压缩文件';

  // Cleaner - cleaned screen outcome
  @override
  String diskCleanerFreeSpaceBeforeAfter(String before, String after) =>
      '可用空间：$before → $after';
  @override
  String get diskCleanerGrowthWatchTitle => '自上次扫描以来的增长';
  @override
  String diskCleanerGrowthWatchLine(String path, String size) =>
      '$path  +$size';

  // Cleaner App Insights
  @override
  String get cleanerUtilitiesTitle => 'CB Agent 清理';
  @override
  String get cleanerUtilitiesSubtitle => '帮助这台电脑保持快速、井井有条的实用工具';
  @override
  String get cleanerUtilitiesStorageGroup => '存储';
  @override
  String get cleanerDiskUsageTitle => '磁盘使用情况';
  @override
  String get cleanerDiskUtilityDescription => '查看文件夹，并安全清理已确认的垃圾文件';
  @override
  String get cleanerAppsTitle => '应用';
  @override
  String get cleanerAppsUtilityDescription => '查找体积大或很少使用的应用，并查看它们的数据';

  // Cleaner - cleanup suggestions
  @override
  String get cleanerSuggestionsTitle => '清理建议';
  @override
  String get cleanerSuggestionsUtilityDescription => '扫描此驱动器上值得清理的内容';
  @override
  String get cleanerSuggestionsIntro =>
      '查找垃圾文件、遗留的安装程序、旧的大文件以及 Windows 可回收的空间，'
      '并说明为什么建议清理每一项。在您确认之前不会删除任何内容，'
      '文件会被移到回收站。';
  @override
  String get cleanerSuggestionsScan => '扫描建议';
  @override
  String get cleanerSuggestionsStepJunk => '正在检查缓存和临时文件...';
  @override
  String get cleanerSuggestionsStepDownloads => '正在检查“下载”文件夹...';
  @override
  String get cleanerSuggestionsStepSystem => '正在检查 Windows 系统文件...';
  @override
  String get cleanerSuggestionsStepDiskScan => '正在查看磁盘使用情况结果...';
  @override
  String cleanerSuggestionsFoundItems(int count) => '找到 $count 个项目';
  @override
  String cleanerSuggestionsFoundSize(String size) => '找到 $size';
  @override
  String get cleanerSuggestionsSourcesTitle => '已检查的来源';
  @override
  String get cleanerSuggestionsSourceDownloads => '“下载”文件夹';
  @override
  String get cleanerSuggestionsSourceSystem => 'Windows 系统文件';
  @override
  String get cleanerSuggestionsSourceDiskScan => '磁盘使用情况结果';
  @override
  String get cleanerSuggestionsTierClean => '可安全清理';
  @override
  String get cleanerSuggestionsTierCleanHint => 'Windows 或应用会自动重新生成。';
  @override
  String get cleanerSuggestionsTierReview => '清理前请查看';
  @override
  String get cleanerSuggestionsTierReviewHint => '通常可以删除，但请确认您不再需要它们。';
  @override
  String get cleanerSuggestionsTierGuided => '使用 Windows 工具释放空间';
  @override
  String get cleanerSuggestionsTierGuidedHint => '请勿直接删除这些内容，请改用建议的工具。';
  @override
  String cleanerSuggestionsReclaimable(String size) => '最多可释放 $size';
  @override
  String cleanerSuggestionsSelected(String size, int count) =>
      '已选择：$count 个项目，共 $size';
  @override
  String get cleanerSuggestionsNothing => '此驱动器上没有发现值得清理的内容。';
  @override
  String get cleanerSuggestionsDiskScanHint =>
      '对此驱动器运行一次磁盘使用情况扫描，还可以找到未使用的大文件、'
      'node_modules 文件夹和虚拟磁盘。';
  @override
  String get cleanerSuggestionsConfirmTitle => '移到回收站？';
  @override
  String cleanerSuggestionsConfirmBody(int count, String size) =>
      '$count 个项目（$size）将被移到回收站。您可以从那里恢复它们。';
  @override
  String cleanerSuggestionsConfirmPersonal(int count) =>
      '其中 $count 个是您自己的文件，不是垃圾。请确保您不再需要它们。';
  @override
  String cleanerSuggestionsConfirmRecycleBin(int count) =>
      '回收站中已有的 $count 个项目将被永久删除。';
  @override
  String cleanerSuggestionsCleaned(String size) =>
      '已清理 $size。移到回收站的文件在回收站清空之前仍会占用空间。';
  @override
  String get cleanerSuggestionsCopyCommand => '复制命令';
  @override
  String cleanerSuggestionsCommandCopied(String command) =>
      '已复制“$command”。请在终端（管理员）中运行。';
  @override
  String get cleanerSuggestionsOpenSettings => '打开 Windows 设置';
  @override
  String cleanerSuggestionsShowItems(int count) => '显示 $count 个项目';
  @override
  String get cleanerSuggestionsHideItems => '隐藏项目';
  @override
  String cleanerSuggestionsAtLeast(String size) => '至少 $size';
  @override
  String cleanerSuggestionsMoreItems(int count) => '... 以及另外 $count 个';
  @override
  String cleanerSuggestionsScanFailed(String error) => '无法扫描建议：$error';
  @override
  String get cleanerSuggestionsJunkScanBusy =>
      '另一项垃圾扫描正在运行（快速清理或 CB Agent），因此已跳过缓存和'
      '临时文件。请在其完成后重新扫描。';
  @override
  String cleanerSuggestionsPartialScan(String error) =>
      '部分扫描失败，因此可能缺少一些建议：$error';
  @override
  String cleanerSuggestionTitle(String id) => switch (id) {
    'downloads_leftovers' => '“下载”中的旧安装程序和压缩文件',
    'old_large_files' => '长期未使用的大文件',
    'node_modules' => 'node_modules 文件夹',
    'hibernation_file' => '休眠文件',
    'previous_windows' => '以前的 Windows 安装',
    'wsl_disk' => 'WSL Linux 磁盘',
    'docker_data' => 'Docker Desktop 数据',
    'virtual_machine_disk' => '虚拟机磁盘',
    'game_library' => '已安装的游戏',
    'phone_backup' => 'iPhone / iPad 备份',
    'android_dev' => 'Android SDK 和模拟器',
    'ai_models' => '已下载的 AI 模型',
    _ => id,
  };
  @override
  String cleanerSuggestionDetail(String id) => switch (id) {
    'downloads_leftovers' => '30 天以上未动过的安装程序、磁盘映像和压缩文件。它们通常只需要用一次。',
    'old_large_files' => '近期没有活动的大型个人文件。旧并不代表不需要：如果不确定，请将它们移到其他驱动器。',
    'node_modules' => 'JavaScript 依赖项。请从不再使用的项目中删除它们；运行“npm install”即可恢复。',
    'hibernation_file' =>
      '用于存储休眠和快速启动所需的内存。如果您不使用休眠，请在管理员终端中运行“powercfg /h off”将其删除。',
    'previous_windows' => 'Windows 升级后保留，以便您回退。升级稳定后，可在“存储”>“临时文件”下将其删除。',
    'wsl_disk' =>
      '不会自行缩小的 Linux 虚拟磁盘。请在 Linux 内部删除文件，运行“wsl --shutdown”，然后压缩磁盘。',
    'docker_data' => '镜像、容器和构建缓存。请用“docker system df”检查，并清理不再需要的内容。',
    'virtual_machine_disk' => '虚拟机磁盘。请在虚拟机管理器中删除不再使用的虚拟机。',
    'game_library' => '请在游戏启动器中卸载不再玩的游戏；之后可以重新下载。',
    'phone_backup' => '来自 Apple 设备 / iTunes 的设备备份。请在该应用中删除旧备份。',
    'android_dev' => '请在 Android Studio 中删除未使用的系统映像和模拟器。',
    'ai_models' => '来自 Ollama 或 LM Studio 等工具的模型文件。请在对应工具中删除不再使用的模型。',
    _ => '',
  };
  @override
  String get cleanerAppsLoading => '正在分析已安装的应用...';
  @override
  String get cleanerAppsUnavailable => '磁盘扫描完成后即可使用应用分析。';
  @override
  String cleanerAppsLoadFailed(String error) => '无法分析已安装的应用：$error';
  @override
  String get cleanerAppsPartialBanner => '结果仍在更新。';
  @override
  String get cleanerAppsSearchHint => '搜索应用';
  @override
  String get cleanerAppsFilterAll => '全部';
  @override
  String get cleanerAppsFilterAttention => '需查看';
  @override
  String get cleanerAppsFilterLarge => '大型';
  @override
  String get cleanerAppsFilterStale => '很少使用';
  @override
  String get cleanerAppsFilterCleanable => '可清理';
  @override
  String get cleanerAppsSortLabel => '排序';
  @override
  String get cleanerAppsSortSize => '最大优先';
  @override
  String get cleanerAppsSortName => '名称';
  @override
  String get cleanerAppsSortLastOpened => '最久未活动';
  @override
  String get cleanerAppsLargeThresholdLabel => '大型应用';
  @override
  String get cleanerAppsStaleThresholdLabel => '未见使用';
  @override
  String cleanerAppsDays(int days) => '$days 天';
  @override
  String get cleanerAppsSummaryFootprint => '已确认的占用';
  @override
  String get cleanerAppsSummaryAttention => '值得查看';
  @override
  String get cleanerAppsSummaryLarge => '大型应用';
  @override
  String get cleanerAppsSummaryStale => '近期未使用';
  @override
  String get cleanerAppsSummaryCleanable => '可清理的缓存';
  @override
  String cleanerAppsThresholdAtLeast(String size) => '$size 或更大';
  @override
  String cleanerAppsNotSeenForDays(int days) => '$days 天内没有启动记录';
  @override
  String get cleanerAppsReviewableCache => '可供安全查看';
  @override
  String cleanerAppsShowingCount(int count) => '显示 $count 个应用';
  @override
  String get cleanerAppsNoResults => '没有符合这些筛选条件的应用。';
  @override
  String get cleanerAppsUnknown => '未知';
  @override
  String cleanerAppsLastOpened(String date) => '最后一次使用：$date';
  @override
  String cleanerAppsNotOpenedForDays(int days) => '已 $days 天未打开';
  @override
  String get cleanerAppsUsageUnknownCompact => '没有近期活动数据';
  @override
  String get cleanerAppsAttentionBadge => '需查看';
  @override
  String get cleanerAppsViewOptions => '视图选项';
  @override
  String cleanerAppsUsageEvidence(String source, String confidence) =>
      '$source • $confidence';
  @override
  String cleanerAppsPossibleSize(String size) => '可能：$size';
  @override
  String cleanerAppsCleanableAmount(String size) => '可清理：$size';
  @override
  String get cleanerAppsDetails => '应用详情';
  @override
  String get cleanerAppsUsageEvidenceLabel => '使用依据';
  @override
  String get cleanerAppsSelectApp => '选择应用以查看其存储情况。';
  @override
  String get cleanerAppsConfirmedFootprint => '已确认';
  @override
  String get cleanerAppsPossibleFootprint => '可能';
  @override
  String get cleanerAppsStorageBreakdown => '存储明细';
  @override
  String get cleanerAppsNoStorageDetails => '此应用没有已测量的存储位置。';
  @override
  String get cleanerAppsSharedFolders => '共享/未归属的大文件夹';
  @override
  String get cleanerAppsSharedFoldersDescription =>
      '这些文件夹不归属于某一个应用，也不会被选中进行清理。';
  @override
  String get cleanerAppsOpenFolder => '打开文件夹';
  @override
  String get cleanerAppsManageInWindows => '在 Windows 中管理';
  @override
  String get cleanerAppsReviewCleanable => '查看可清理的数据';
  @override
  String get cleanerAppsAskAgent => '询问 CB Agent';
  @override
  String cleanerAppsVersion(String version) => '版本 $version';
  @override
  String cleanerAppsInstalledOrUpdated(String date) => '安装或更新时间：$date';
  @override
  String get cleanerAppsSourceWin32 => 'Win32 应用';
  @override
  String get cleanerAppsSourceStore => 'Microsoft Store 应用';
  @override
  String get cleanerAppsMeasurementMeasured => '已测量';
  @override
  String get cleanerAppsMeasurementEstimated => 'Windows 估算';
  @override
  String get cleanerAppsMeasurementPartial => '部分';
  @override
  String get cleanerAppsMeasurementUnknown => '大小未知';
  @override
  String get cleanerAppsAttributionConfirmed => '已确认';
  @override
  String get cleanerAppsAttributionPossible => '可能';
  @override
  String get cleanerAppsAttributionShared => '共享';
  @override
  String get cleanerAppsUsageUserAssist => 'Windows 启动历史';
  @override
  String get cleanerAppsUsagePrefetch => 'Windows 预读取';
  @override
  String get cleanerAppsConfidenceHigh => '高可信度';
  @override
  String get cleanerAppsConfidenceMedium => '中等可信度';
  @override
  String get cleanerAppsStorageInstall => '安装';
  @override
  String get cleanerAppsStorageLocalData => '本地应用数据';
  @override
  String get cleanerAppsStorageRoamingData => '漫游应用数据';
  @override
  String get cleanerAppsStoragePackageData => '软件包数据';
  @override
  String get cleanerAppsStorageProgramData => '共享程序数据';
  @override
  String get cleanerAppsStorageCache => '缓存';
  @override
  String get cleanerAppsStorageLogs => '日志';
  @override
  String get cleanerAppsStorageShared => '共享存储';
  @override
  String get cleanerAppsStorageUnknown => '其他存储';
  @override
  String get cleanerAppsCleanableBadge => '可清理';

  @override
  String get aiThinking0 => '正在思考...';
  @override
  String get aiThinking1 => '正在分析...';
  @override
  String get aiThinking2 => '正在搜索...';
  @override
  String get aiThinking3 => '正在生成回复...';
  @override
  String get aiWaitingApproval => '正在等待您的批准...';
  @override
  String aiRunningTool(String toolName) => '正在运行 $toolName...';

  // Local AI Advisor
  @override
  String get localAiAdvisor => '本地 AI 顾问';
  @override
  String get localAiAdvisorDescription => '使用您自己的 Gemma 4 模型，在设备上生成清理建议';
  @override
  String get huggingFaceToken => 'Hugging Face 令牌';
  @override
  String get huggingFaceTokenHint => '可选：用于私有模型或访问扩展目录';
  @override
  String get pasteToken => '粘贴令牌';
  @override
  String get tokenSaved => '令牌已安全保存';
  @override
  String get clearToken => '清除令牌';
  @override
  String get browseModels => '浏览模型';
  @override
  String get installedModels => '已安装的模型';
  @override
  String get noModelsInstalled => '尚未安装模型';
  @override
  String get installModel => '安装';
  @override
  String get uninstallModel => '卸载';
  @override
  String get selectActiveModel => '设为当前';
  @override
  String get modelInstalling => '正在安装模型...';
  @override
  String get modelInstalled => '模型安装成功';
  @override
  String get modelUninstalled => '模型已卸载';
  @override
  String get downloadProgress => '下载进度';
  @override
  String get noTokenSet => '未设置令牌';
  @override
  String get setTokenFirst => '请先设置您的 Hugging Face 令牌';
  @override
  String get openLocation => '打开位置';
  @override
  String get localAiIncompatibleArtifact =>
      '此模型文件与设备端聊天不兼容。请重新安装 LiteRT-LM 版本以启用本地聊天。';
  @override
  String get localAiReinstallCompatible => '重新安装兼容的模型';
  @override
  String get localAiContextWindow => '上下文窗口';
  @override
  String get localAiContextWindowHint =>
      '每次聊天的最大 Token 数（提示词 + 回复）。数值越大，越能处理更大的文件和更长的对话，但占用的内存也越多。';
  @override
  String get localAiTokensSuffix => 'Token';
  @override
  String get localAiInvalidTokenCount => '请输入有效的数字';
  @override
  String get aiReasoning => '思考';

  @override
  String get sshLocalConfig => '来自 ~/.ssh/config';
  @override
  String get sshLocalConfigHint => '选择一个本地主机以填入连接详情。';
  @override
  String get sshNoLocalConfig => '在 ~/.ssh/config 中未找到主机。请在下方输入主机。';
  @override
  String get sshLocalKeys => '此电脑上的密钥';
  @override
  String get sshLocalKeysHint => '在 ~/.ssh 中检测到。选择一个密钥，将其导入安全保管库。';
  @override
  String get sshChooseKeyFile => '选择密钥文件';
  @override
  String get sshPasteKey => '粘贴私钥';
  @override
  String get sshPassphraseHint => '仅当私钥已加密时才需要。';
  @override
  String get sshImportHint => '使用本地文件，或粘贴 OpenSSH / PEM 私钥。';
  @override
  String get sshGenerateHint => '创建 Ed25519 密钥。保存后，请将其公钥复制到您的服务器。';
  @override
  String get sshKeyImportFailed => '无法保存密钥。请检查文件、格式和密码，然后重试。';
  @override
  String get sshConnectionDetails => '连接详情';
  @override
  String get sshLocalKeyPending => '保存或连接时将导入此本地密钥。';
  @override
  String get sshConfigUnsupported => '此主机使用了此处不支持的代理或 SSH 证书。连接前请检查其设置。';
  @override
  String get sshDiscoveryIncomplete =>
      '部分本地 SSH 设置无法加载（文件不可读或存在条件 Match 规则）。请检查已填入的详情。';

  // App updates
  @override
  String get checkForUpdates => '检查更新';
  @override
  String get updateChecking => '正在检查更新…';
  @override
  String get updateUpToDate => '您使用的已是最新版本';
  @override
  String get updateAvailableTitle => '有可用更新';
  @override
  String get updateAvailableGeneric => '有新版本可用';
  @override
  String get updateDownload => '下载';
  @override
  String get updateDownloading => '正在下载更新…';
  @override
  String get updateStoreDownloading => '应用商店正在下载更新…';
  @override
  String get updateReadyTitle => '更新已可安装';
  @override
  String get updateReadyMessage => '应用将关闭以安装更新，然后重新打开。继续之前请保存您的工作。';
  @override
  String get updateAdminHint => 'Windows 将请求管理员权限。';
  @override
  String get updateInstallNow => '安装并重启';
  @override
  String get updateLater => '稍后';
  @override
  String get updateInstalling => '正在安装更新…';
  @override
  String get updateFailed => '更新失败';
  @override
  String get updateRetry => '重试';
  @override
  String get updateReleaseNotes => '新增内容';
  @override
  String get updateAction => '更新';
  @override
  String updateAvailableVersion(String version) => '版本 $version 已可用';
  @override
  String updateCurrentVersion(String version) => '当前版本：$version';
  @override
  String get updateStatusSection => '应用更新';
  @override
  String get updateSectionFeatures => '新功能';
  @override
  String get updateSectionFixes => '修复';
  @override
  String get updateSectionImprovements => '改进';
  @override
  String get updateMinorChanges => '细节修复和稳定性改进。';
  @override
  String get updateBackgroundHint => '更新将在后台下载。您可以关闭此窗口，并通过通知铃铛查看进度。';

  // Hardcoded-string cleanup
  @override
  String get chooseLocation => '选择位置';
  @override
  String get navigationHistoryLabel => '导航历史';
  @override
  String get selectCommonTagsToRemove => '选择要移除的共同标签：';
  @override
  String get streamCreateFailed => '无法串流此文件。请检查您的网络连接，然后重试。';
  @override
  String errorOpeningVideo(String error) => '打开视频时出错：$error';
  @override
  String unexpectedFileOpenError(String error) => '打开文件时发生意外错误：$error';
  @override
  String get enterPath => '输入路径...';
  @override
  String get clearCompleted => '清除已完成项';
  @override
  String get running => '运行中';
  @override
  String get notifications => '通知';
  @override
  String get dismiss => '忽略';
  @override
  String get openFileLocation => '打开文件所在位置';
  @override
  String get minimize => '最小化';
  @override
  String get maximize => '最大化';
  @override
  String get tabInactiveTooltip => '不活动（60 分钟后自动挂起）';
  @override
  String get closeSplitView => '关闭分屏';
  @override
  String get nothingToShow => '没有可显示的内容';
  @override
  String get albumNotFound => '未找到相册';
  @override
  String get invalidAlbumId => '无效的相册 ID';
  @override
  String get videoLibraryNotFound => '未找到视频库';
  @override
  String get invalidVideoLibraryId => '无效的视频库 ID';
  @override
  String get vpAdvancedControls => '高级控制';
  @override
  String get vpAudioTracks => '音轨';
  @override
  String get vpAudioTracksStub => '音轨选择功能将在此处实现。';
  @override
  String get vpSubtitles => '字幕';
  @override
  String get vpPlaybackSpeed => '播放速度';
  @override
  String vpPlaybackSpeedValue(String speed) => '播放速度（${speed}x）';
  @override
  String get vpPictureInPicture => '画中画';
  @override
  String get vpExitPip => '退出画中画';
  @override
  String get vpVideoFilters => '视频滤镜';
  @override
  String get vpSleepTimer => '睡眠定时器';
  @override
  String get vpSleepTimerActive => '睡眠定时器（已启用）';
  @override
  String get vpVideoSettings => '视频设置';
  @override
  String get vpReset => '重置';
  @override
  String get vpResetToDefault => '恢复默认';
  @override
  String get vpOff => '关闭';
  @override
  String vpHoursOption(int hours) => '$hours 小时';
  @override
  String vpMinutesOption(int minutes) => '$minutes 分钟';
  @override
  String get vpBrightness => '亮度';
  @override
  String get vpContrast => '对比度';
  @override
  String get vpSaturation => '饱和度';
  @override
  String get vpStreamSpeed => '串流速度';
  @override
  String get vpBufferInfo => '缓冲信息';
  @override
  String get vpRewind10 => '后退 10 秒';
  @override
  String get vpForward10 => '快进 10 秒';
  @override
  String get vpCodec => '编解码器：';
  @override
  String get vpAuto => '自动';
  @override
  String get vpScaleMode => '视频缩放模式：';
  @override
  String get vpScaleContain => '适应窗口（保持比例，不裁剪）';
  @override
  String get vpScaleCover => '覆盖（填充并裁剪）';
  @override
  String get vpScaleFill => '填充（拉伸）';
  @override
  String get vpScaleFitWidth => '适应宽度';
  @override
  String get vpScaleFitHeight => '适应高度';
  @override
  String get vpScaleNone => '无（原始大小）';
  @override
  String get vpScaleDown => '缩小';
  @override
  String get vpAudioDecoder => '音频解码器：';
  @override
  String get vpSoftware => '软件';
  @override
  String get vpHardware => '硬件';
  @override
  String vpBufferSize(int mb) => '缓冲区大小：${mb}MB';
  @override
  String vpNetworkTimeout(int seconds) => '网络超时：$seconds 秒';
  @override
  String get vpSubtitleEncoding => '字幕编码：';
  @override
  String get vpOutputFormat => '视频输出格式：';
  @override
  String get remove => '移除';
  @override
  String get cancelSelection => '取消选择';
  @override
  String get deselectAll => '取消全选';
  @override
  String albumRemoveImagesTitle(int count) => '移除 $count 张图片？';
  @override
  String get albumRemoveImagesBody => '要从此相册中移除所选图片吗？原始文件不会被删除。';
  @override
  String get albumNever => '从未';
  @override
  String albumSmartStatus(int rules, int sources, String last) =>
      '$rules 条规则 • $sources 个来源 • 上次：$last';
  @override
  String get albumScanningFiles => '正在扫描文件...';
  @override
  String albumAddingFiles(int current, int total) =>
      '正在添加文件...（$current/$total）';
  @override
  String get albumCompleted => '已完成！';
  @override
  String get albumScanning => '正在扫描...';
  @override
  String get albumNoScanLocations => '未配置扫描位置';
  @override
  String albumScanningFound(int count) => '正在扫描... 已找到 $count 个';
  @override
  String albumCompletedFound(int count) => '已完成！找到 $count 个文件';
  @override
  String get albumCanceled => '已取消';
  @override
  String get albumScanLocations => '扫描位置';
  @override
  String get albumNoLocationsSelected => '未选择位置。请添加要为此相册扫描的文件夹。';
  @override
  String get albumAddFolder => '添加文件夹';
  @override
  String get albumEditAlbum => '编辑相册';
  @override
  String get albumManageRules => '管理规则';
  @override
  String get albumShuffle => '随机排序';
  @override
  String get albumUnshuffle => '取消随机排序';
  @override
  String get albumAddImagesTooltip => '添加图片';
  @override
  String get albumRemoveFromAlbum => '从相册中移除';
  @override
  String get albumMoveSelectedToTrash => '将所选文件移到回收站';
  @override
  String albumSearchImagesIn(String name) => '在 $name 中搜索图片';
  @override
  String get albumSmartLabel => '智能相册（按规则动态生成）';
  @override
  String get albumSources => '来源';
  @override
  String get albumRescan => '重新扫描';
  @override
  String get albumRules => '规则';
  @override
  String get albumNoImages => '此相册中没有图片';
  @override
  String get albumNoImagesMatch => '没有与您的搜索匹配的图片';
  @override
  String get albumAddImagesHint => '添加图片，开始构建您的相册';
  @override
  String get albumAddImages => '添加图片';
  @override
  String albumDeleteOneConfirm(String name) => '确定要删除相册“$name”吗？此操作无法撤销。';
  @override
  String albumDeleteManyConfirm(int count) => '确定要删除 $count 个相册吗？此操作无法撤销。';
  @override
  String get albumDeletedOne => '相册已成功删除';
  @override
  String albumDeletedMany(int count) => '已成功删除 $count 个相册';
  @override
  String albumDeleteFailedCount(int count) => '删除 $count 个相册失败';
  @override
  String albumImageCount(int count) => '$count 张图片';
  @override
  String get albumColumnPrivacy => '隐私';
  @override
  String get albumPublic => '公开';
  @override
  String albumSourceCount(int count) => '$count 个来源';
  @override
  String get albumSourceSettings => '来源设置';
  @override
  String get albumEditAlbumLower => '编辑相册';
  @override
  String get albumSetCover => '设置封面…';
  @override
  String get albumRandomCover => '随机封面';
  @override
  String get albumOptions => '相册选项';
  @override
  String get albumSearchSources => '搜索图片来源';
  @override
  String get albumSearchAlbums => '搜索相册';
  @override
  String get albumNoMatchingResults => '没有匹配的结果';
  @override
  String get albumNoSourcesYet => '还没有图片来源';
  @override
  String get albumNoAlbumsYet => '还没有相册';
  @override
  String get albumAddSourceHint => '添加来源，即可浏览其文件夹中的图片';
  @override
  String get albumCreateFirstHint => '创建您的第一个相册来整理图片';
  @override
  String get albumCreateImageSource => '创建图片来源';
  @override
  String get albumCreateAlbum => '创建相册';
  @override
  String get albumBadgeSource => '来源';
  @override
  String get albumNoImagesForCover => '没有可选作封面的图片';
  @override
  String get albumChooseCover => '选择封面图片';
  @override
  String get ruleDeleteTitle => '删除规则';
  @override
  String ruleDeleteConfirm(String name) => '确定要删除规则“$name”吗？';
  @override
  String get ruleCreateNew => '新建规则';
  @override
  String get ruleEmptyTitle => '自动相册规则';
  @override
  String get ruleEmptyBody => '创建匹配文件名模式的规则，\n自动整理您的照片';
  @override
  String get ruleCreateFirst => '创建您的第一条规则';
  @override
  String get ruleExScreenshots => '截图';
  @override
  String get ruleExScreenshotsDesc => '包含“screenshot”的文件 → 截图相册';
  @override
  String get ruleExCamera => '相机照片';
  @override
  String get ruleExCameraDesc => '以“IMG_”开头的文件 → 相机相册';
  @override
  String get ruleExEdited => '已编辑的照片';
  @override
  String get ruleExEditedDesc => '以“_edited”结尾的文件 → 已编辑相册';
  @override
  String get rulePopularExamples => '常用规则示例';
  @override
  String ruleAlbumLabel(String name) => '相册：$name';
  @override
  String ruleConditionLabel(String name) => '条件：$name';
  @override
  String rulePatternLabel(String pattern) => '模式：“$pattern”';
  @override
  String get ruleMatches => '匹配数';
  @override
  String get ruleLastTriggered => '上次触发';
  @override
  String ruleDaysAgo(int n) => '$n 天前';
  @override
  String ruleHoursAgo(int n) => '$n 小时前';
  @override
  String ruleMinutesAgo(int n) => '$n 分钟前';
  @override
  String get ruleJustNow => '刚刚';
  @override
  String get ruleCreateAutoRule => '创建自动规则';
  @override
  String get ruleCreate => '创建规则';
  @override
  String get ruleQuickTemplates => '快速模板';
  @override
  String get ruleQuickTemplatesHint => '选择一个预设模板，快速开始';
  @override
  String get ruleExamples => '示例：';
  @override
  String get ruleCustom => '自定义规则';
  @override
  String get ruleName => '规则名称';
  @override
  String get ruleNameHint => '例如：截图归入截图相册';
  @override
  String get ruleTargetAlbum => '目标相册';
  @override
  String get ruleCondition => '条件';
  @override
  String get rulePattern => '模式';
  @override
  String get rulePreview => '预览';
  @override
  String get rulePreviewHint => '查看哪些文件会匹配您的规则';
  @override
  String get rulePreviewUpdatedHint => '查看哪些文件会匹配您更新后的规则';
  @override
  String get ruleTestResults => '测试结果：';
  @override
  String get ruleCondContains => '包含';
  @override
  String get ruleCondStartsWith => '开头是';
  @override
  String get ruleCondEndsWith => '结尾是';
  @override
  String get ruleCondEquals => '等于';
  @override
  String get ruleCondRegex => '正则表达式';
  @override
  String get ruleHintContains => '例如：screenshot';
  @override
  String get ruleHintStartsWith => '例如：IMG_';
  @override
  String get ruleHintEndsWith => '例如：_edited';
  @override
  String get ruleHintEquals => '例如：photo';
  @override
  String get ruleHintRegex => r'例如：^IMG_\d{4}$';
  @override
  String get ruleEditAutoRule => '编辑自动规则';
  @override
  String get ruleSaveChanges => '保存更改';
  @override
  String get ruleDetails => '规则详情';
  @override
  String errorWithDetail(String error) => '错误：$error';
  @override
  String get albumSelectingFiles => '正在选择文件...';
  @override
  String get albumAddingSelectedFiles => '正在添加所选文件...';
  @override
  String get albumAddTo => '添加到相册';
  @override
  String get albumAddFromFolder => '从文件夹添加';
  @override
  String get albumAddFromFolderDesc => '添加所选文件夹中的所有图片';
  @override
  String get albumAddSelectedPhotos => '添加所选照片';
  @override
  String get albumAddSelectedPhotosDesc => '选择要添加的特定图片文件';
  @override
  String get albumColorOptional => '相册颜色（可选）';
  @override
  String get albumEditTitle => '编辑相册';
  @override
  String get albumCreateTitle => '新建相册';
  @override
  String get albumNameRequiredLabel => '相册名称 *';
  @override
  String get albumNameHint => '输入相册名称';
  @override
  String get albumNameRequired => '必须填写相册名称';
  @override
  String get albumNameTooLong => '相册名称不能超过 50 个字符';
  @override
  String get albumDescriptionLabel => '描述（可选）';
  @override
  String get albumDescriptionHint => '输入相册描述';
  @override
  String get albumDescriptionTooLong => '描述不能超过 200 个字符';
  @override
  String get albumDynamicSmart => '动态（智能）相册';
  @override
  String get albumDynamicSmartDesc => '内容由自动规则决定，不会显式存储任何文件。';
  @override
  String get albumAddingFilesToAlbum => '正在将文件添加到相册...';
  @override
  String get albumSearchAndSelect => '搜索并选择图片';
  @override
  String get albumSearchForImages => '搜索图片...';
  @override
  String albumSelectedOfTotal(int selected, int total) =>
      '已选择 $selected / $total';
  @override
  String get albumDeselectAllCaps => '取消全选';
  @override
  String get albumLoadingImages => '正在加载图片...';
  @override
  String get albumNoImagesFound => '未找到图片';
  @override
  String get albumTryDifferentSearch => '请尝试其他搜索词';
  @override
  String albumAddNImages(int count) => '添加 $count 张图片';
  @override
  String get albumAddFolderToAlbum => '将文件夹添加到相册';
  @override
  String get albumAddAllFromFolder => '要将此文件夹中的所有图片添加到相册吗？';
  @override
  String albumFolderName(String name) => '文件夹：$name';
  @override
  String get albumIncludeSubfolders => '包含子文件夹中的图片';
  @override
  String get albumAddFolderButton => '添加文件夹';
  @override
  String get albumAddingFolder => '正在将文件夹添加到相册...';
  @override
  String albumImagesCountShort(int count) => '$count 张图片';
  @override
  String get albumNoImagesShort => '没有图片';
  @override
  String get albumCounting => '正在统计...';
  @override
  String get albumGoUp => '返回上级';
  @override
  String get albumSelectFolderTitle => '选择文件夹';
  @override
  String get albumNoFoldersFound => '未找到文件夹';
  @override
  String albumCurrentFolder(String name) => '当前：$name';
  @override
  String get albumAddThisFolder => '添加此文件夹';
  @override
  String ivShareFailed(String error) => '无法分享图片：$error';
  @override
  String get ivPrintSent => '图片已发送到打印机';
  @override
  String get ivPrintFailed => '无法开始打印此图片';
  @override
  String get ivDisplayFailed => '无法显示图片';
  @override
  String get ivNoImages => '没有可显示的图片';
  @override
  String get previous => '上一个';
  @override
  String get next => '下一个';
  @override
  String get ivInfo => '信息 (I)';
  @override
  String get ivMore => '更多';
  @override
  String get ivZoomOut => '缩小';
  @override
  String get ivZoomIn => '放大';
  @override
  String get ivRotateLeft => '向左旋转';
  @override
  String get ivRotateRight => '向右旋转';
  @override
  String get ivEditImage => '编辑图片';
  @override
  String get ivPauseSlideshow => '暂停幻灯片';
  @override
  String get ivPlaySlideshow => '播放幻灯片';
  @override
  String get ivExitFullscreen => '退出全屏';
  @override
  String get ivFullscreen => '全屏';
  @override
  String get ivPrint => '打印 (Ctrl+P)';
  @override
  String get ivResetZoom => '重置缩放 (0)';
  @override
  String get ivCopyPath => '复制文件路径';
  @override
  String get ivHideThumbnails => '隐藏缩略图';
  @override
  String get ivShowThumbnails => '显示缩略图';
  @override
  String get edDiscardTitle => '放弃更改？';
  @override
  String get edDiscardBody => '您的编辑尚未保存。';
  @override
  String get edDiscard => '放弃';
  @override
  String get edSaveDialogTitle => '保存编辑后的副本';
  @override
  String get edSavedCopy => '已保存编辑后的副本';
  @override
  String edSaveFailed(String error) => '无法保存图片：$error';
  @override
  String edEraseFailed(String error) => '无法擦除：$error';
  @override
  String get edAddText => '添加文字';
  @override
  String get edTypeSomething => '输入内容';
  @override
  String get add => '添加';
  @override
  String get edCloseEditor => '关闭编辑器 (Esc)';
  @override
  String get edTitle => '编辑';
  @override
  String get edUndo => '撤销 (Ctrl+Z)';
  @override
  String get edRedo => '重做 (Ctrl+Y)';
  @override
  String get edHoldToCompare => '按住以对比';
  @override
  String get edSaving => '正在保存...';
  @override
  String get edSaveCopy => '保存副本';
  @override
  String get edToolCrop => '裁剪';
  @override
  String get edToolAdjust => '调整';
  @override
  String get edToolFilters => '滤镜';
  @override
  String get edToolMarkup => '标注';
  @override
  String get edToolErase => '擦除';
  @override
  String get edAspectRatio => '宽高比';
  @override
  String get edAspectFree => '自由';
  @override
  String get edAspectOriginal => '原始';
  @override
  String get edRotateFlip => '旋转和翻转';
  @override
  String get edFlipHorizontal => '水平翻转';
  @override
  String get edFlipVertical => '垂直翻转';
  @override
  String get edLightColour => '光线与色彩';
  @override
  String get edExposure => '曝光';
  @override
  String get edWarmth => '色温';
  @override
  String get edTint => '色调';
  @override
  String get edVignette => '暗角';
  @override
  String get edStrength => '强度';
  @override
  String get edFilterVivid => '鲜艳';
  @override
  String get edFilterWarm => '暖色';
  @override
  String get edFilterCool => '冷色';
  @override
  String get edFilterFade => '褪色';
  @override
  String get edFilterDramatic => '戏剧';
  @override
  String get edFilterMono => '单色';
  @override
  String get edFilterNoir => '黑色电影';
  @override
  String get edFilterSepia => '怀旧';
  @override
  String get edTool => '工具';
  @override
  String get edPen => '画笔';
  @override
  String get edHighlighter => '荧光笔';
  @override
  String get edArrow => '箭头';
  @override
  String get edLine => '直线';
  @override
  String get edRectangle => '矩形';
  @override
  String get edEllipse => '椭圆';
  @override
  String get edText => '文字';
  @override
  String get edEraseMarkup => '擦除标注';
  @override
  String get edColour => '颜色';
  @override
  String get edTextSize => '文字大小';
  @override
  String get edSize => '大小';
  @override
  String get edTextHint => '在图片上点击要放置文字的位置。';
  @override
  String get edEraseTitle => '擦除';
  @override
  String get edEraseHint => '涂抹要移除的内容，系统会根据周围区域进行填充。对小物体和瑕疵效果最佳。';
  @override
  String get edBrush => '画刷';
  @override
  String edOpenFailed(String error) => '无法打开此图片进行编辑。\n$error';
  @override
  String get edErasing => '正在擦除...';
  @override
  String get edOriginal => '原始';
  @override
  String get edDoubleClickReset => '双击以重置';
  @override
  String get cachePhotoThumbs => '照片缩略图';
  @override
  String get cachePhotoThumbsDesc => '为图片网格和查看器生成的 JPEG 预览';
  @override
  String get cacheVideoThumbs => '视频缩略图';
  @override
  String get cacheVideoThumbsDesc => '视频的缓存画面预览';
  @override
  String get cacheNetworkThumbs => '网络缩略图';
  @override
  String get cacheNetworkThumbsDesc => 'SMB / FTP / WebDAV 缩略图缓存';
  @override
  String get cacheLibrary => '视频库缓存';
  @override
  String get cacheLibraryDesc => '视频库元数据和缓存的内容';
  @override
  String get cacheTempFiles => '临时文件';
  @override
  String get cacheTempFilesDesc => '临时下载文件和工作文件';
  @override
  String cacheLoadFailed(String error) => '加载缓存信息失败：$error';
  @override
  String get cacheOpenFolderFailed => '无法在系统资源管理器中打开文件夹';
  @override
  String cacheEntryCleared(String name) => '$name 已清除';
  @override
  String cacheEntryClearFailed(String name, String error) =>
      '清除 $name 失败：$error';
  @override
  String get cacheAllCleared => '所有缓存已清除';
  @override
  String cacheClearFailed(String error) => '清除缓存失败：$error';
  @override
  String get cacheTotalSize => '总大小';
  @override
  String get cacheFilesLabel => '文件';
  @override
  String get cacheBuckets => '分类';
  @override
  String cacheFilesCount(int count) => '$count 个文件';
  @override
  String cachePercentOfTotal(String percent) => '占全部缓存的 $percent%';
  @override
  String dbLoadPrefsFailed(String error) => '加载数据库偏好设置时出错：$error';
  @override
  String get dbClearAllWarning => '这将删除所有应用设置，包括主题、语言和视图偏好。应用可能会重新启动。';
  @override
  String get dbNoPrefs => '没有存储的偏好设置。';
  @override
  String dbRowsCount(int count) => '$count 行';
  @override
  String dbRangeOfTotal(int start, int end, int total) =>
      '$start-$end，共 $total';
  @override
  String get dbRowsPerPage => '每页行数';
  @override
  String dbPageOf(int page, int total) => '第 $page / $total 页';
  @override
  String get faNoData => '没有可用数据';
  @override
  String get faShowInHub => '在图库中心显示精选相册';
  @override
  String get faAutoSelect => '自动选择最近的相册';
  @override
  String get faAutoSelectDesc => '自动将您最近的相册设为精选';
  @override
  String get faMax => '精选相册上限';
  @override
  String get faManual => '手动选择精选相册';
  @override
  String get laNoTokenInClipboard => '剪贴板中没有令牌';
  @override
  String get laRemoveModelConfirm => '要从您的设备中移除此模型吗？';
  @override
  String laOpenLocationFailed(String error) => '无法打开位置：$error';
  @override
  String get laRuntimePending => '运行时待定';
  @override
  String get laRequiresGguf => '需要 GGUF';
  @override
  String get laInstallFailed => '安装失败';
  @override
  String get laDownloading => '正在下载...';
  @override
  String tagTabName(String tag) => '标签：$tag';
  @override
  String tagThumbnailSet(String tag) => '已为“$tag”设置缩略图';
  @override
  String get tagThumbnailSetFailed => '设置缩略图失败';
  @override
  String tagThumbnailRemoved(String tag) => '已移除“$tag”的缩略图';
  @override
  String get tagThumbnailRemoveFailed => '移除缩略图失败';
  @override
  String tagHasChildren(int count, String children) =>
      '此标签有 $count 个子标签：$children';
  @override
  String get tagWhatToDo => '您想怎么做？';
  @override
  String get tagDeleteParentOnly => '仅删除父标签';
  @override
  String get tagDeleteParentAndChildren => '删除父标签和子标签';
  @override
  String tagsDeletedList(int count, String tags) => '已删除 $count 个标签：$tags';
  @override
  String tagCannotAddChild(String name) => '无法添加“$name” - 存在循环引用或出错';
  @override
  String tagCannotSetParent(String name) => '无法将“$name”设为父标签 - 存在循环引用或出错';
  @override
  String tagHierarchyTitle(String tag) => '层级：“$tag”';
  @override
  String get tagNoParents => '没有父标签';
  @override
  String get tagNoChildren => '没有子标签';
  @override
  String get tagAddParentHint => '添加父标签...';
  @override
  String get tagAddChildHint => '添加子标签...（用逗号分隔）';
  @override
  String get tagQuickPicks => '快速选择';
  @override
  String get tagQuickPicksDesc => '从热门标签和最近使用的标签中选择';
  @override
  String get tagBrowseTreeDesc => '浏览标签树 — 展开父标签即可选择其子标签。';
  @override
  String get tagSearchTitle => '按标签搜索';
  @override
  String get tagSearchInputLabel => '输入要搜索的标签';
  @override
  String get tagSearchInputHint => '例如：重要, 工作, 个人';
  @override
  String get tagSearchGlobal => '全局搜索';
  @override
  String get tagSearchGlobalDesc => '在设备上的任意位置搜索';
  @override
  String get tagSearchNoTags => '没有可用的标签';
  @override
  String get newMenu => '新建';
  @override
  String get customizeMenu => '自定义...';
  @override
  String get fileCreateFailedDetail => '文件可能已存在，或目标位置不可写';
  @override
  String get customizeNewMenuTitle => '自定义“新建”菜单';
  @override
  String folderFilesFolders(int files, int folders) =>
      '$files 个文件，$folders 个文件夹';
  @override
  String dndMoved(int count) => '已移动 $count 个项目';
  @override
  String get dndFolderIntoItself => '无法将文件夹移动到其自身中';
  @override
  String get dndLocalOnly => '拖放仅支持本地路径';
  @override
  String get dndDestinationMissing => '目标文件夹不可用';
  @override
  String get dndMoveFailed => '移动失败';
  @override
  String get toggleView => '切换视图';
  @override
  String get folderNameLabelShort => '文件夹名称';
  @override
  String get vfPickFrame => '从视频中选取画面';
  @override
  String get vfExtractFailed => '提取画面失败。请尝试其他位置。';
  @override
  String get pause => '暂停';
  @override
  String get play => '播放';
  @override
  String vfPreviewAt(String time) => '预览位置 $time';
  @override
  String get preview => '预览';
  @override
  String get vfUseFrame => '使用此画面';
  @override
  String get cfCsvSpreadsheet => 'CSV 表格';
  @override
  String get cfNoTemplates => '没有可用的模板';
  @override
  String cfNoResultsFor(String query) => '没有“$query”的结果';
  @override
  String cfExtension(String ext) => '扩展名：$ext';
  @override
  String cfCreatesFile(String ext) => '创建 $ext 文件';
  @override
  String mpDriveSystem(String letter) => '$letter（系统）';
  @override
  String mpDriveOther(String letter) => '$letter（驱动器）';
  @override
  String get tagManageHierarchy => '管理层级';
  @override
  String get tagFilterParent => '父标签';
  @override
  String get tagFilterChild => '子标签';
  @override
  String get tagFilterStandalone => '独立标签';
  @override
  String get tagFilterHasThumb => '有缩略图';
  @override
  String get tagFilterNoThumb => '无缩略图';
  @override
  String get tagFilterAll => '全部';
  @override
  String get tagFilterTitle => '筛选标签';
  @override
  String get tagManageHierarchyTooltip => '管理层级（父/子）';
  @override
  String get tagDoubleClickChildren => '双击以打开子标签';
  @override
  String get tagDoubleClickFiles => '双击以打开文件';
  @override
  String get tagHierarchyFormatHelp =>
      '请使用 父标签:子标签 的格式表示层级\n例如 演员:小明 或 演员:小明,小红';
  @override
  String get tagInvalidFormat => '格式无效。请使用 父标签:子标签 或 父标签:子标签1,子标签2';
  @override
  String get tagNoChildSpecified => '未指定子标签';
  @override
  String tagRelationFailed(String parent, String child) =>
      '无法创建关系：$parent -> $child（存在循环引用？）';
  @override
  String tagHierarchyCreated(String parent, String children, int count) =>
      '已创建层级：$parent -> $children（$count 个关系）';
  @override
  String get tagCircularHierarchy => '无法创建循环的标签层级';
  @override
  String tagMovedUnder(String child, String parent) => '已将“$child”移到“$parent”下';
  @override
  String get aiViewRawPayload => '查看原始请求数据';
  @override
  String get aiViewPayload => '查看请求数据';
  @override
  String get aiProviderError => '提供商错误';
  @override
  String get aiToolActivity => '工具活动';
  @override
  String aiContextInfo(int messages, String chars) =>
      '$messages 条消息 · $chars 个字符\n上下文裁剪将在约 24K 字符时开始';
  @override
  String get aiAllDrives => '所有驱动器';
  @override
  String get aiThinking => '正在思考...';
  @override
  String get aiDropToMention => '拖放以提及';
  @override
  String aiFilesAttached(int count) => '已附加 $count 个文件';
  @override
  String get aiStopGeneration => '停止生成';
  @override
  String aiLinkCopied(String href) => '链接已复制：$href';
  @override
  String get aiJustNow => '刚刚';
  @override
  String aiMinutesAgo(int n) => '$n 分钟前';
  @override
  String aiHoursAgo(int n) => '$n 小时前';
  @override
  String aiDaysAgo(int n) => '$n 天前';
  @override
  String get aiFileNotFound => '未找到文件';
  @override
  String get aiOpenFolderTooltip => '打开文件夹';
  @override
  String get aiOpenFileTooltip => '打开文件';
  @override
  String get aiNoPayload => '尚未捕获请求数据。请先发送一条消息，即可查看请求。';
  @override
  String get aiRawApiPayload => '原始 API 请求数据';
  @override
  String get aiCopiedToClipboard => '已复制到剪贴板';
  @override
  String get aiStreaming => '流式';
  @override
  String get aiNonStreaming => '非流式';
  @override
  String get aiLoadingContent => '正在加载内容...';
  @override
  String aiMoreLines(int count) => '...（还有 $count 行）';
  @override
  String get aiToolOk => '成功';
  @override
  String get aiToolFailed => '失败';
  @override
  String foErrorCopying(String error) => '复制时出错：$error';
  @override
  String foErrorCutting(String error) => '剪切时出错：$error';
  @override
  String foErrorPasting(String error) => '粘贴时出错：$error';
  @override
  String foErrorRenaming(String error) => '重命名时出错：$error';
  @override
  String get foNothingToPaste => '没有可粘贴的内容 — 剪贴板为空';
  @override
  String foMovingOne(String name) => '正在移动“$name”';
  @override
  String foCopyingOne(String name) => '正在复制“$name”';
  @override
  String foMovingMany(int count) => '正在移动 $count 个项目';
  @override
  String foCopyingMany(int count) => '正在复制 $count 个项目';
  @override
  String foMoveProgress(int done, int total, String dest) =>
      '正在将第 $done 项（共 $total 项）移动到 $dest';
  @override
  String foCopyProgress(int done, int total, String dest) =>
      '正在将第 $done 项（共 $total 项）复制到 $dest';
  @override
  String foMovedItems(int count, String dest) => '已将 $count 个项目移动到 $dest';
  @override
  String foCopiedItems(int count, String dest) => '已将 $count 个项目复制到 $dest';
  @override
  String get foMovingVerb => '正在移动';
  @override
  String get foCopyingVerb => '正在复制';
  @override
  String foPasteDetailNoSource(String action, int count, String dest) =>
      '$action $count 个项目到 $dest';
  @override
  String foPasteDetail(
    String action,
    String source,
    String from,
    String dest,
  ) => '$action $source，从 $from 到 $dest';
  @override
  String foAndMore(String name, int more) => '$name 以及另外 $more 个';
  @override
  String foDeleteDetail(String action, String item, String parent) =>
      '$action：$item（位于 $parent）';
  @override
  String get foActionPermanentDelete => '永久删除';
  @override
  String get foActionMoveToTrash => '移到回收站';
  @override
  String foDeletingOnePerm(String name) => '正在永久删除“$name”';
  @override
  String foDeletingOneTrash(String name) => '正在将“$name”删除到回收站';
  @override
  String foDeletingFilesPerm(int count) => '正在永久删除 $count 个文件';
  @override
  String foDeletingFilesTrash(int count) => '正在将 $count 个文件删除到回收站';
  @override
  String foDeletingItemsPerm(int count) => '正在永久删除 $count 个项目';
  @override
  String foMovingOneTrash(String name) => '正在将“$name”移到回收站';
  @override
  String foMovingItemsTrash(int count) => '正在将 $count 个项目移到回收站';
  @override
  String foPermDeletedProgress(int done, int total) => '已永久删除 $done / $total';
  @override
  String foTrashedProgress(int done, int total) => '已移到回收站 $done / $total';
  @override
  String foPermDeletedFiles(int count) => '已永久删除 $count 个文件';
  @override
  String foTrashedFiles(int count) => '已将 $count 个文件移到回收站';
  @override
  String foPermDeletedItems(int count) => '已永久删除 $count 个项目';
  @override
  String foTrashedItems(int count) => '已将 $count 个项目移到回收站';
  @override
  String foAdminDeletingOne(String name) => '正在以管理员身份删除“$name”';
  @override
  String foAdminDeletingMany(int count) => '正在以管理员身份删除 $count 个项目';
  @override
  String get foAdminWaiting => '正在等待 Windows 管理员批准';
  @override
  String foAdminDeletedOne(String path) => '已以管理员身份删除“$path”。';
  @override
  String foAdminDeletedMany(int count) => '已以管理员身份删除 $count 个项目。';
  @override
  String foAdminFailedOne(String path) => '管理员删除“$path”已取消或失败。';
  @override
  String foAdminFailedMany(int count) => '管理员删除 $count 个项目已取消或失败。';
  @override
  String get foDeleteFailed => '删除失败';
  @override
  String foFirstFailureItems(int count, String path) =>
      '$count 个项目；首个失败项：“$path”';
  @override
  String foCouldNotDeleteAccessDenied(String item) =>
      '无法删除 $item：访问被拒绝。请检查文件夹权限，或以管理员身份运行应用。';
  @override
  String foCouldNotDeleteReason(String item, String reason) =>
      '无法删除 $item：$reason。';
  @override
  String foCouldNotDelete(String item) => '无法删除 $item。';
  @override
  String get fnDirNotExist => '目录不存在';
  @override
  String get fnStoragePermission => '需要存储权限';
  @override
  String fnErrorSorting(String error) => '排序时出错：$error';
  @override
  String fnInvalidRegex(String error) => '无效的正则表达式：$error';
  @override
  String get fnAccessDeniedAdmin => '访问被拒绝。请尝试以管理员身份运行。';
  @override
  String tsErrorLoadingTags(String error) => '加载标签时出错：$error';
  @override
  String tsErrorAddingTag(String error) => '添加标签时出错：$error';
  @override
  String tsErrorRemovingTag(String error) => '移除标签时出错：$error';
  @override
  String tsErrorBatchAdding(String error) => '批量添加标签时出错：$error';
  @override
  String tsTagSearchError(String error) => '标签搜索出错：$error';
  @override
  String tsGlobalTagSearchError(String error) => '全局标签搜索出错：$error';
  @override
  String tsMultiTagSearchError(String error) => '多标签搜索出错：$error';
  @override
  String tsGlobalMultiTagSearchError(String error) => '全局多标签搜索出错：$error';
  @override
  String get jlTemp => '临时';
  @override
  String get jlBrowser => '浏览器';
  @override
  String get jlRecycle => '回收站';
  @override
  String get jlThumbs => '缩略图';
  @override
  String get jlAppCache => '应用缓存';
  @override
  String get jlCrashLog => '崩溃/日志';
  @override
  String get jlWinUpdate => 'WIN 更新';
  @override
  String get jlPrefetch => '预读取';
  @override
  String get jlDelivery => '传递优化';
  @override
  String get jlDevCache => '开发缓存';
  @override
  String get jlJunk => '垃圾';
  @override
  String get treeLoadFailedRetry => '加载失败。点击重试。';
  @override
  String cleanerRefreshFailed(String error) => '刷新失败：$error';
  @override
  String cleanerLoadPropsFailed(String error) => '加载属性失败：$error';
  @override
  String get aiProviderNameHint => '我的 OpenAI';
  @override
  String get aiSystemPromptHint => '可选的自定义系统提示词...';
  @override
  String get vlNameHint => '我的电影';
  @override
  String get vlDescriptionHint => '个人电影收藏';
}
