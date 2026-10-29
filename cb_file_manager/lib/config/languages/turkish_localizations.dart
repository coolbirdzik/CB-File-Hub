import 'app_localizations.dart';

class TurkishLocalizations implements AppLocalizations {
  @override
  String get sshProxy => 'Vekil sunucu';
  @override
  String get sshProxies => 'Vekil sunucular';
  @override
  String get sshAddProxy => 'Vekil sunucu ekle';
  @override
  String get sshEditProxy => 'Vekil sunucuyu düzenle';
  @override
  String get sshProxyType => 'Vekil sunucu protokolü';
  @override
  String get sshProxyNone => 'Doğrudan bağlantı';
  @override
  String get sshProxyHint =>
      'Vekil sunucu bilgileri işletim sistemi kasasında saklanır. HTTP Basic, SOCKS5 kullanıcı adı/parola, SOCKS4a kullanıcı kimliği destekler.';
  @override
  String get sshProxyInvalid =>
      'Geçerli bir vekil sunucu adresi, port (1–65535) ve kimlik bilgileri girin.';
  @override
  String get sshProxyInUse =>
      'Kayıtlı bir sunucu bu vekili kullanıyor. Silmeden önce sunucuyu değiştirin.';
  @override
  String get sshNoProxies =>
      'Vekil sunucu ekleyin veya başka bir SSH uygulamasından içe aktarın.';
  @override
  String get sshImportProxyFailed =>
      'Sunucu atlandı: vekil sunucu eksik, geçersiz veya desteklenmiyor. Bağlanmadan önce vekili yapılandırın.';
  @override
  String sshProxyImportSummary(
    int hosts,
    int keys,
    int proxies,
    int duplicates,
  ) =>
      '$hosts sunucu, $keys anahtar ve $proxies vekil içe aktarıldı; $duplicates tekrar atlandı.';
  @override
  String get sshImportScan => 'Yüklü uygulamaları tara';
  @override
  String get sshImportFileMode => 'Dosyadan içe aktar';
  @override
  String get sshImportScanHint =>
      'Yüklü SSH uygulamalarındaki yerel sunucuları ve anahtarları otomatik okur. Kaynakları ve öğeleri seçip içe aktarın. Kaynak veriler korunur.';
  @override
  String get sshImportNotFound => 'Bu bilgisayarda bulunamadı';
  @override
  String get sshImportVaultLocked =>
      'Termius verileri açılamadı. Bu işletim sistemi hesabıyla Termius kilidini açıp yeniden tarayın.';
  @override
  String get sshImportScanFailed =>
      'Bu kaynak okunamadı. SSH istemcisini kapatıp yeniden tarayın.';
  @override
  String sshImportFound(int hosts, int keys) =>
      '$hosts sunucu ve $keys anahtar bulundu.';
  @override
  String get sshImportFromApp => 'Başka uygulamadan içe aktar';
  @override
  String get sshImportAppHint =>
      'Yüklü SSH uygulamalarını otomatik tarayıp sunucuları ve anahtarları içe aktarın. Kaydetmeden önce seçimi inceleyin.';
  @override
  String get sshImportSource => 'Kaynak biçimi';
  @override
  String get sshImportAuto => 'Otomatik algıla';
  @override
  String get sshImportChooseFiles =>
      'Dışa aktarma / özel anahtar dosyaları ekle';
  @override
  String get sshImportPaste => 'Dışa aktarılan veriyi yapıştır';
  @override
  String get sshImportPreview => 'Önizleme';
  @override
  String get sshImportSelected => 'Seçilenleri içe aktar';
  @override
  String get sshImportTermiusHint =>
      'Yüklü uygulamaları tara seçeneği Termius verilerini doğrudan okur. Taşınabilir dışa aktarma için CSV / JSON / OpenSSH dosyaları ve özel anahtarları ekleyin. PPK v2/v3 anahtarları doğrudan desteklenir.';
  @override
  String get sshImportPassphraseHint =>
      'Şifreli anahtar dosyaları için isteğe bağlı parola. Dışa aktarmadaki anahtara özel parolalar önceliklidir.';
  @override
  String get sshImportEmpty =>
      'İçe aktarılabilir sunucu veya özel anahtar bulunamadı.';
  @override
  String get sshImportMissingKey =>
      'Sunucu atlandı: özel anahtar eksik veya belirsiz. İlgili dosyayı ekleyip yeniden önizleyin.';
  @override
  String get sshImportUnsupported =>
      'Atlama sunucusu, yönlendirme veya koşullu ayarlar aktarılamaz. Bağlanmadan önce sunucuyu inceleyin.';
  @override
  String get sshImportPasswordMissing =>
      'Kayıtlı parola şifreli veya dışa aktarmada yok. İçe aktardıktan sonra sunucu düzenleyicisinde girin.';
  @override
  String get sshImportUnknownFormat =>
      'Desteklenmeyen veya geçersiz dışa aktarma biçimi.';
  @override
  String get sshImportLimit =>
      'Sınır: 128 dosya, dosya başına 8 MB, toplam 32 MB, belge başına 2.000 öğe.';
  @override
  String get sshImportReadFailed =>
      'Dışa aktarma okunamadı. Biçimi, kodlamayı ve dosya boyutunu kontrol edin.';
  @override
  String get sshImportSaveFailed =>
      'Kimlik bilgisi kasasına kaydedilemedi. Hiçbir öğe aktarılmadı; kasa kullanılabilir olduğunda yeniden deneyin.';
  @override
  String sshImportSummary(int hosts, int keys, int duplicates) =>
      '$hosts sunucu ve $keys anahtar içe aktarıldı; $duplicates tekrar atlandı.';

  @override
  String get aiProviderKind => 'Sağlayıcı türü';
  @override
  String get aiProviderCustom => 'Özel';
  @override
  String get deviceMediaOnDevice => 'Bu cihazda';
  @override
  String get deviceMediaLimited =>
      'Yalnızca erişimine izin verdiğiniz fotoğraf ve videolar gösteriliyor.';
  @override
  String get deviceMediaPermission =>
      'Cihaz albümlerini göstermek için fotoğraf ve video erişimine izin verin.';
  @override
  String get deviceMediaManageAccess => 'Daha fazla fotoğraf ve video seçin';
  @override
  String get torrentReceiveInBackground =>
      'Açılan torrentleri arka planda ekle';
  @override
  String get torrentReceiveInBackgroundHint =>
      'İletişim kutusu göstermez ve pencereyi öne getirmez. Görev çubuğunu yanıp söndürür ve bildirim gönderir. Kayıtlı indirme klasörünü (ayarlanmamışsa Downloads) ve hemen başlat tercihini kullanır; mevcut görevleri değiştirmez.';
  @override
  String get torrentBackgroundAdded => 'Torrent alındı';
  @override
  String get torrentBackgroundFailed => 'Torrent eklenemedi';
  @override
  String get torrentOpeningOptions => 'Torrent açarken';
  @override
  String get torrentShowDownloadDialog =>
      'Torrent açarken indirme seçeneklerini göster';
  @override
  String get torrentShowDownloadDialogHint =>
      'Kapalıyken kayıtlı indirme klasörü ve hemen başlatma tercihi kullanılır. Klasör kaydedilmemişse seçim istenir.';
  @override
  String get torrentImportMenu => 'İçe aktar';
  @override
  String torrentImportFrom(String app) => '$app uygulamasından içe aktar';
  @override
  String get torrentClientImportHint =>
      'Bulunan profilden kayıtlı .torrent dosyalarını içe aktarın veya başka bir klasör seçin. Seçili depolama modu uygulanır. İndirilen içerik korunur.';
  @override
  String get torrentClientNotFound =>
      'Profil bulunamadı. Uygulamanın .torrent dosyalarını sakladığı klasörü seçin.';
  @override
  String get torrentClientSourceRequired =>
      '.torrent dosyalarını içeren mevcut bir klasör seçin.';
  @override
  String get torrentAddLink => 'Bağlantıdan torrent ekle';
  @override
  String get torrentLinkHint =>
      'HTTP/HTTPS torrent adresi veya magnet bağlantısı yapıştırın.';
  @override
  String get torrentRefreshImport => 'Yeni torrentleri içe aktar (F5)';
  @override
  String get torrentStartImmediately => 'İndirmeyi hemen başlat';
  @override
  String get torrentDestinationRequired =>
      'Bir indirme klasörü seçin veya tam yolunu girin.';
  @override
  String get torrentDestinationLocked =>
      'İndirme klasörünü değiştirmeden önce görevi durdurun.';
  @override
  String shellColumn(String column) =>
      const {
        'owner': 'Sahip',
        'ownerHint': 'Öğenin sahibi olan hesap',
        'authors': 'Yazarlar',
        'authorsHint': 'Belge veya medya yazarları',
        'title': 'Başlık',
        'titleHint': 'Dosyada saklanan başlık',
        'comments': 'Açıklamalar',
        'commentsHint': 'Dosyada saklanan açıklamalar',
        'pageCount': 'Sayfa',
        'pageCountHint': 'Belgenin sayfa sayısı',
        'rating': 'Derecelendirme',
        'ratingHint': 'Yıldız derecelendirmesi',
        'dateTaken': 'Çekim tarihi',
        'dateTakenHint': 'Fotoğrafın çekildiği zaman',
        'cameraModel': 'Kamera modeli',
        'cameraModelHint': 'Fotoğrafı çeken kamera',
        'frameRate': 'Kare hızı',
        'frameRateHint': 'Videonun saniyedeki kare sayısı',
        'bitRate': 'Bit hızı',
        'bitRateHint': 'Ses veya videonun bit hızı',
        'artist': 'Katkıda bulunan sanatçılar',
        'artistHint': 'Şarkının sanatçıları',
        'album': 'Albüm',
        'albumHint': 'Şarkının albümü',
        'genre': 'Tür',
        'genreHint': 'Şarkı veya video türü',
        'year': 'Yıl',
        'yearHint': 'Yayın yılı',
        'company': 'Şirket',
        'companyHint': 'Programın veya belgenin şirketi',
        'fileDescription': 'Dosya açıklaması',
        'fileDescriptionHint': 'Programın açıklaması',
        'fileVersion': 'Dosya sürümü',
        'fileVersionHint': 'Programın veya kitaplığın sürümü',
        'productName': 'Ürün adı',
        'productNameHint': 'Programın ait olduğu ürün',
      }[column] ??
      column;
  @override
  String torrentColumn(String column) =>
      const {
        'status': 'İndirme durumu',
        'progress': 'İlerleme',
        'downSpeed': 'İndirme hızı',
        'upSpeed': 'Yükleme hızı',
        'seeds': 'Kaynaklar',
        'peers': 'Eşler',
        'eta': 'Kalan süre',
        'downloaded': 'İndirilen',
        'uploaded': 'Yüklenen',
        'ratio': 'Paylaşım oranı',
        'files': 'Dosya sayısı',
        'group': 'Grup',
        'destination': 'İndirme klasörü',
        'hash': 'Bilgi özeti',
        'remaining': 'Kalan',
        'tracker': 'İzleyici',
        'trackerCount': 'İzleyiciler',
        'torrentCreated': 'Torrent oluşturulma',
        'createdBy': 'Oluşturan',
        'comment': 'Açıklama',
        'private': 'Gizlilik',
        'privateYes': 'Özel',
        'privateNo': 'Herkese açık',
        'pieceSize': 'Parça boyutu',
        'pieceCount': 'Parçalar',
        'metainfoSize': 'Torrent dosya boyutu',
        'torrentFile': 'Torrent dosyası',
        'source': 'Kaynak',
        'error': 'Hata',
        'taskId': 'Görev kimliği',
        'filters': 'Torrentleri filtrele',
        'seedsHint': 'Bu indirmeye şu anda bağlı olan kaynak sayısı.',
        'peersHint':
            'Kaynaklar ve web kaynakları dahil bağlı eşlerin toplam sayısı.',
      }[column] ??
      column;
  @override
  String get torrentStatusLabel => 'Durum';
  @override
  String get torrents => 'Torrentler';
  @override
  String get torrentDuplicateTitle => 'Torrent zaten var';
  @override
  String get torrentDuplicateHint =>
      'İzleyiciler ve kaynaklar birleştirilsin mi? İndirme durumu, hedef klasör ve mevcut dosyalar korunur.';
  @override
  String get torrentMerge => 'Birleştir';
  @override
  String get torrentReveal => 'Listede göster';
  @override
  String torrentSaved(String name) => 'Kaydedildi: $name';
  @override
  String get torrentCopyMagnet => 'Magnet bağlantısını kopyala';
  @override
  String get torrentAddMagnet => 'Magnet bağlantısı ekle';
  @override
  String get torrentDefaultApps => 'Windows varsayılanlarını seç';
  @override
  String get torrentDefaultAppsHint =>
      'Windows Varsayılan uygulamalar bölümünde .torrent dosyaları ve MAGNET bağlantıları için CB File Hub\'ı seçin.';
  @override
  String get torrentOrganize => 'Torrent dosyalarını düzenle';
  @override
  String torrentStorageMode(String mode) =>
      const {
        'index': 'Yalnızca dizinle, orijinalleri koru',
        'copy': 'Seçilen depolama klasörüne kopyala',
        'move': 'Seçilen depolama klasörüne taşı',
      }[mode] ??
      mode;
  @override
  String get torrentSubtitle =>
      'Dosyalarınız nerede olursa olsun tek bir kütüphane.';
  @override
  String get torrentStorage => 'Torrent depolama klasörü';
  @override
  String get torrentStorageHint =>
      'Kopyalama, dizindeki torrentleri karma değerine göre düzenler. Taşıma, doğrulanmış kopyası bulunan mevcut orijinalleri temizlemeden önce onay ister. Sonraki içe aktarmalar seçilen modu kullanır. İndirme hedefleri ayrıca seçilir.';
  @override
  String get torrentMoveConfirmTitle =>
      'Torrentler taşınsın ve kaynaklar temizlensin mi?';
  @override
  String torrentMoveConfirmHint(int count) =>
      'Aşağıda $count kaynak .torrent dosyası listelenmiştir. Her orijinal yalnızca depolanan kopya doğrulandıktan sonra kaldırılır. İndirilen içerik ve diğer kaynak dosyaları korunur. Sonraki içe aktarmalar Taşı modunu kullanır.';
  @override
  String get torrentMoveConfirm => 'Taşıma ve temizlemeyi onayla';
  @override
  String get torrentImport => '.torrent içe aktar';
  @override
  String get qbittorrentImport => 'qBittorrent içe aktar';
  @override
  String get qbittorrentImportHint =>
      'Windows BT_backup klasörlerini otomatik bulur veya taşınabilir profili seçebilirsiniz. Torrent ve .fastresume yedekleri seçilen klasöre kopyalanır. .torrent eksikse magnet olarak aktarılır; indirmeyi seçtiğinizde metadata alınır.';
  @override
  String get qbittorrentChooseSource => 'BT_backup seç';
  @override
  String get qbittorrentRemoveSources =>
      'İçe aktardıktan sonra qBittorrent kaynaklarını kaldır';
  @override
  String get qbittorrentRemoveHint =>
      'Eşleşen .torrent ve .fastresume dosyalarını temizler. Önce qBittorrent uygulamasını kapatın; indirilen içerik korunur.';
  @override
  String get qbittorrentConfirmTitle =>
      'Bu torrentler qBittorrent içinden kaldırılsın mı?';
  @override
  String qbittorrentConfirmHint(int count) =>
      'CB File Hub kopyayı kaydedip doğruladıktan sonra yalnızca aşağıdaki $count kaynak dosyasını temizler. İndirilen içerik ve diğer dosyalar korunur. qBittorrent kapalı olmalıdır.';
  @override
  String get qbittorrentConfirm => 'İçe aktarma ve temizlemeyi onayla';
  @override
  String qbittorrentFound(int torrents, int files) =>
      '$torrents torrent · $files kaynak dosyası';
  @override
  String qbittorrentProgress(int completed, int total) =>
      '$completed / $total torrent aktarılıyor';
  @override
  String qbittorrentResult(int stored, int cleaned, int failed) =>
      'Kaydedildi: $stored · Temizlendi: $cleaned · Hata: $failed';
  @override
  String qbittorrentProblem(String problem) =>
      const {
        'running':
            'qBittorrent uygulamasını tamamen kapatıp tekrar deneyin. Yalnızca kopyalamak için kaynak temizlemeyi kapatın.',
        'sqlite':
            'Bu profilde torrents.db var. BT_backup temizliği SQLite kayıtlarını kaldırmaz; kaynaklar korundu. Fastresume profili seçin.',
        'changed':
            'Önizlemeden sonra kaynak değişti. Kaynak korundu; listeyi yenileyin.',
        'destination': 'BT_backup kaynak klasörü dışında bir hedef seçin.',
        'missingMetainfo':
            '.torrent dosyası veya geçerli dizin kopyası bulunamadı. .fastresume korundu.',
        'noSources': 'BT_backup bulunamadı. qBittorrent veri klasörünü seçin.',
      }[problem] ??
      problem;
  @override
  String get torrentScanFolder => 'Klasörü tara';
  @override
  String get torrentScanSystem => 'Tüm yerel sürücüleri tara';
  @override
  String get torrentAutoImport =>
      'Kaynak klasörleri her 5 dakikada bir otomatik içe aktar';
  @override
  String get torrentSources => 'İçe aktarma kaynakları';
  @override
  String get torrentEngine => 'aria2c yürütülebilir dosyasını seç';
  @override
  String get torrentDownload => 'Şuraya indir…';
  @override
  String get torrentPause => 'Duraklat';
  @override
  String get torrentResume => 'Devam et';
  @override
  String get torrentStop => 'İndirmeyi durdur';
  @override
  String get torrentGroup => 'Grup';
  @override
  String get torrentRemove => 'Dizinden kaldır';
  @override
  String get torrentRemoveHint =>
      'İndirme duracaktır. Torrent meta bilgileri, orijinaller ve indirilen dosyalar diskte kalır. Sonraki bir tarama bunu yeniden içe aktarabilir.';
  @override
  String get torrentEmpty =>
      'Torrent bulunamadı. Başlamak için dosyaları içe aktarın veya bir klasörü tarayın.';
  @override
  String get torrentScanHint =>
      'Torrent istemcisi yedekleri dahil, bağlı tüm yerel sürücülerdeki .torrent dosyalarını tarar. Dosyalar içeriğe göre gruplanır ve tekilleştirilir. Mevcut istemci indirme konumları ve oturumları içe aktarılmaz.';
  @override
  String get torrentScanLog => 'Tarama hata günlüğünü aç';
  @override
  String get torrentNoStorage =>
      'İçe aktarmadan önce torrent meta bilgilerinin saklanacağı yeri seçin.';
  @override
  String get torrentOpenFolder => 'İndirme klasörünü aç';
  @override
  String get torrentDesktopOnly =>
      'Torrent indirmeleri masaüstü aria2 gerektirir. Erişilebilir yerel klasörlerde dizinleme kullanılabilir.';
  @override
  String torrentStatus(String status) =>
      const {
        'library': 'Kütüphane',
        'active': 'İndiriliyor',
        'waiting': 'Sırada',
        'paused': 'Duraklatıldı',
        'complete': 'Tamamlandı',
        'error': 'Başarısız',
      }[status] ??
      status;
  @override
  String torrentCategory(String category) =>
      const {
        'video': 'Video',
        'audio': 'Ses',
        'documents': 'Belgeler',
        'other': 'Diğer',
      }[category] ??
      category;
  @override
  String torrentScanSummary(
    int visited,
    int imported,
    int duplicates,
    int failed,
  ) =>
      '$visited torrent denetlendi · $imported içe aktarıldı · $duplicates yinelenen · $failed hata';
  @override
  String get torrentFilesPerPage => 'Sayfa başına dosya';
  @override
  String torrentPageSummary(int first, int last, int total) =>
      '$total torrentin $first–$last arası';
  @override
  String get galleryNsfwLabel => 'NSFW içerik';
  @override
  String get galleryNsfwDescription =>
      'Bu koleksiyonun görsellerini ve video önizlemelerini Ana Sayfa\'da gösterme.';

  @override
  String get homeSubtitle =>
      'Klasörleriniz, fotoğraflarınız ve videolarınız hep elinizin altında.';
  @override
  String get homeRecentFolders => 'Kaldığınız yerden devam edin';
  @override
  String get homeRecentEmpty =>
      'Ziyaret ettiğiniz klasörler burada görünür. Başlamak için bir klasör açın.';
  @override
  String get homeRecentUnavailable => 'Son klasörler yüklenemedi.';
  @override
  String get homePhotosSubtitle =>
      'Fotoğraf koleksiyonunuzdan küçük bir ilham.';
  @override
  String get homeVideosSubtitle => 'Video koleksiyonunuz keşfedilmeye hazır.';
  @override
  String get homePinnedEmpty =>
      'Hızlı erişim için favori klasörlerinizi dosya tarayıcısından sabitleyin.';

  @override
  String get sshDisplayName => 'Ad';
  @override
  String get sshRequired => 'Bu alan zorunludur.';
  @override
  String get sshInvalidHost =>
      'URL veya yol olmadan bir ana bilgisayar adı ya da IP adresi girin.';
  @override
  String get sshInvalidPort => '1 ile 65535 arasında bir port girin.';

  @override
  String get sshWorkspace => 'SSH çalışma alanı';
  @override
  String get sshHosts => 'Ana bilgisayarlar';
  @override
  String get sshKeys => 'SSH anahtarları';
  @override
  String get sshKnownHosts => 'Güvenilen ana bilgisayarlar';
  @override
  String get sshAddHost => 'Ana bilgisayar ekle';
  @override
  String get sshEditHost => 'Ana bilgisayarı düzenle';
  @override
  String get sshGenerateKey => 'Ed25519 anahtarı oluştur';
  @override
  String get sshImportKey => 'Özel anahtarı içe aktar';
  @override
  String get sshOpenTerminal => 'Terminali aç';
  @override
  String get sshBrowseFiles => 'SFTP\'ye göz at';
  @override
  String get sshGroup => 'Grup';
  @override
  String get sshAuthMethod => 'Kimlik doğrulama';
  @override
  String get sshPasswordAuth => 'Parola';
  @override
  String get sshKeyAuth => 'SSH anahtarı';
  @override
  String get sshNoHosts =>
      'Bir terminal açmak veya dosyalarına göz atmak için SSH ana bilgisayarı ekleyin.';
  @override
  String get sshNoKeys =>
      'Bir özel anahtarı içe aktarın veya Ed25519 anahtarı oluşturun.';
  @override
  String get sshNoTrustedHosts =>
      'Bir bağlantıyı onayladıktan sonra ana bilgisayar parmak izleri burada görünür.';
  @override
  String get sshPrivateKey => 'Özel anahtar (OpenSSH / PEM)';
  @override
  String get sshPassphrase => 'Anahtar parolası';
  @override
  String get sshCopyPublicKey => 'Genel anahtarı kopyala';
  @override
  String get sshTrustHost => 'Bu SSH ana bilgisayarına güvenilsin mi?';
  @override
  String get sshHostKeyChanged => 'SSH ana bilgisayar anahtarı değişti';
  @override
  String get sshVerifyFingerprint =>
      'Güvenmeden önce bu parmak izini sunucu yöneticisiyle doğrulayın.';
  @override
  String get sshTrustAndConnect => 'Güven ve bağlan';
  @override
  String get sshForgetHost => 'Güvenilen ana bilgisayarı unut';
  @override
  String get sshDeleteConfirm => 'Bu kayıtlı öğe kaldırılsın mı?';
  @override
  String get sshKeyInUse =>
      'Silmeden önce bu anahtarı kullanan ana bilgisayarların kimlik doğrulamasını değiştirin.';
  @override
  String get sshConnecting => 'Bağlanılıyor…';
  @override
  String get sshDisconnected => 'Oturum bağlantısı kesildi';
  @override
  String get sshReconnect => 'Yeniden bağlan';
  @override
  String get sshClearTerminal => 'Terminali temizle';
  @override
  String get sshVaultHint =>
      'Parolalar ve özel anahtarlar bu cihazdaki güvenli depolamada saklanır.';
  @override
  String get ftpSecurity => 'Bağlantı güvenliği';
  @override
  String get ftpPlain => 'FTP (şifresiz)';
  @override
  String get ftpExplicitTls => 'FTPS — Açık TLS (21)';
  @override
  String get ftpImplicitTls => 'FTPS — Örtük TLS (990)';

  @override
  String get appTitle => 'CB File Hub';

  // Common actions
  @override
  String get ok => 'Tamam';
  @override
  String get cancel => 'İptal';
  @override
  String get save => 'Kaydet';
  @override
  String get delete => 'Sil';
  @override
  String get edit => 'Düzenle';
  @override
  String get close => 'Kapat';
  @override
  String get exit => 'Çıkış';
  @override
  String get search => 'Ara';
  @override
  String get all => 'Tümü';
  @override
  String get settings => 'Ayarlar';

  @override
  String get moreOptions => 'Diğer seçenekler';
  @override
  String get thirdPartyApps => 'Üçüncü taraf uygulamalar';
  @override
  String get configureContextMenu => 'Bağlam menüsünü yapılandır';
  @override
  String get contextMenuLayout => 'Bağlam menüsü düzeni';
  @override
  String get contextMenuLayoutDescription =>
      'Sağ tıkladığınızda gösterilen komutları yeniden sıralayın veya gizleyin';
  @override
  String get contextMenuLayoutHint =>
      'Komutları yeniden sıralamak için sürükleyin. Gizli komutlar burada kullanılabilir kalır.';
  @override
  String get contextMenuForFiles => 'Dosyalar';
  @override
  String get contextMenuForFolders => 'Klasörler';
  @override
  String get contextMenuForMultipleItems => 'Birden çok öğe';
  @override
  String get resetContextMenuLayout => 'Düzeni sıfırla';
  @override
  String get contextMenuLayoutReset => 'Bağlam menüsü düzeni sıfırlandı';

  // File operations
  @override
  String get copy => 'Kopyala';
  @override
  String get cut => 'Kes';
  @override
  String get move => 'Taşı';
  @override
  String get rename => 'Yeniden adlandır';
  @override
  String get newFolder => 'Yeni klasör';
  @override
  String get properties => 'Özellikler';
  @override
  String get openWith => 'Birlikte aç';
  @override
  String get chooseDefaultApp => 'Varsayılan uygulamayı seç';

  @override
  String get useSelectedAppAsVideoDefault =>
      'CB File Hub\'daki videolar için seçilen uygulamayı varsayılan olarak kullan';
  @override
  String get applicationsLoadError => 'Uygulamalar yüklenemedi.';
  @override
  String get noApplicationsFound => 'Bu dosya türü için uygulama bulunamadı.';
  @override
  String get setCoolBirdAsDefaultForVideos =>
      'CB File Hub\'ı video dosyaları için varsayılan yap';
  @override
  String get setCoolBirdAsDefaultForVideosAndroidHint =>
      'Ayarlar açılıyor. "Varsayılan olarak aç" bölümünde video dosyaları için CB File Hub\'ı etkinleştirin.';
  @override
  String get setCoolBirdAsDefaultForArchives =>
      'CB File Hub\'ı arşiv dosyaları için varsayılan yap';
  @override
  String get setCoolBirdAsDefaultForArchivesSuccess =>
      'CB File Hub artık arşiv dosyaları için varsayılan.';
  @override
  String get setCoolBirdAsDefaultForArchivesFailed =>
      'CB File Hub arşiv dosyaları için varsayılan yapılamadı.';
  @override
  String get openFolder => 'Klasörü aç';
  @override
  String get openFile => 'Dosyayı aç';
  @override
  String get viewImage => 'Görseli görüntüle';
  @override
  String get open => 'Aç';
  @override
  String get pasteHere => 'Buraya yapıştır';
  @override
  String get manage => 'Yönet';

  @override
  String get manageTags => 'Etiketleri yönet';
  @override
  String get moveToTrash => 'Çöp kutusuna taşı';

  @override
  String get errorAccessingDirectory => 'Dizine erişim hatası';
  @override
  String errorAccessingDirectoryWithError(String error) =>
      'Dizine erişim hatası: $error';
  @override
  String accessDeniedAdminMessage(String path) =>
      'Erişim reddedildi: $path konumuna erişmek için yönetici ayrıcalıkları gerekir';
  @override
  String directoryDoesNotExist(String path) => 'Dizin mevcut değil: $path';

  // Action bar tooltips
  @override
  String get searchTooltip => 'Ara';

  @override
  String get sortByTooltip => 'Sırala';

  @override
  String get refreshTooltip => 'Yenile';

  @override
  String get moreOptionsTooltip => 'Diğer seçenekler';

  @override
  String get adjustGridSizeTooltip => 'Öğe boyutunu ayarla';

  @override
  String get columnSettingsTooltip => 'Sütun ayarları';

  @override
  String get viewModeTooltip => 'Görünüm modu';

  // Dialog titles
  @override
  String get adjustGridSizeTitle => 'Öğe boyutunu ayarla';

  @override
  String get columnVisibilityTitle => 'Sütun görünümünü özelleştir';

  // Button labels
  @override
  String get apply => 'UYGULA';

  // Sort options
  @override
  String get sortNameAsc => 'Ad (A → Z)';

  @override
  String get sortNameDesc => 'Ad (Z → A)';

  @override
  String get sortDateModifiedOldest => 'Değiştirilme tarihi (önce en eski)';

  @override
  String get sortDateModifiedNewest => 'Değiştirilme tarihi (önce en yeni)';

  @override
  String get sortDateCreatedOldest => 'Oluşturulma tarihi (önce en eski)';

  @override
  String get sortDateCreatedNewest => 'Oluşturulma tarihi (önce en yeni)';

  @override
  String get sortSizeSmallest => 'Boyut (önce en küçük)';

  @override
  String get sortSizeLargest => 'Boyut (önce en büyük)';

  @override
  String get sortTypeAsc => 'Dosya türü (A → Z)';

  @override
  String get sortTypeDesc => 'Dosya türü (Z → A)';

  @override
  String get sortExtensionAsc => 'Uzantı (A → Z)';

  @override
  String get sortExtensionDesc => 'Uzantı (Z → A)';

  @override
  String get sortAttributesAsc => 'Öznitelikler (A → Z)';

  @override
  String get sortAttributesDesc => 'Öznitelikler (Z → A)';

  @override
  String get sortDateAccessedOldest => 'Erişim tarihi (Önce en eski)';

  @override
  String get sortDateAccessedNewest => 'Erişim tarihi (Önce en yeni)';

  @override
  String get sortPathAsc => 'Yol (A → Z)';

  @override
  String get sortPathDesc => 'Yol (Z → A)';

  // View modes
  @override
  String get viewModeList => 'Liste';

  @override
  String get viewModeGrid => 'Izgara';

  @override
  String get viewModeDetails => 'Ayrıntılar';

  @override
  String get viewModeGridPreview => 'Izgara + Önizleme';

  @override
  String get viewModeColumns => 'Sütunlar';

  @override
  String get viewModeTree => 'Ağaç';

  @override
  String get viewModeTiles => 'Kutucuklar';

  @override
  String get defaultViewMode => 'Varsayılan görünüm modu';

  @override
  String get defaultViewModeDescription =>
      'Kendi kayıtlı görünüm modu olmayan klasörler için kullanılır';

  @override
  String get propertiesAndTags => 'Özellikler ve etiketler';
  @override
  String get showPropertiesPane => 'Özellikleri ve etiketleri göster';
  @override
  String get hidePropertiesPane => 'Özellikleri ve etiketleri daralt';
  @override
  String get propertiesSelectFile =>
      'Özelliklerini ve etiketlerini görmek için bir dosya seçin.';
  @override
  String get propertiesFilesOnly =>
      'Etiketler yalnızca seçili dosyalara uygulanır.';
  @override
  String get propertiesTagFailure => 'Bazı dosyalar güncellenemedi';
  @override
  String get propertiesResize => 'Özellikler panelini yeniden boyutlandır';
  @override
  String get propertiesTagHint => 'Etiket adı veya üst:alt';

  @override
  String get previewPaneTitle => 'Önizleme';

  @override
  String get dragFilePane =>
      'Başka bir bölmenin yanına yerleştirmek için sürükleyin';

  @override
  String get resetFilePaneLayout => 'Varsayılan bölme düzenini geri yükle';

  @override
  String get previewSelectFile => 'Önizlemek için bir dosya seçin';

  @override
  String get previewNotSupported =>
      'Bu dosya türü için önizleme kullanılamıyor';

  @override
  String get archiveSectionTitle => 'Arşiv';

  @override
  String get archiveBrowseTitle => 'İçeriğe göz at';

  @override
  String get archiveExtractHere => 'Buraya çıkar';

  @override
  String get archiveExtractTo => 'Şuraya çıkar…';

  @override
  String get archiveExtractToTitle => 'Çıkarma klasörünü seçin';

  @override
  String get archiveExtractAll => 'Tümünü çıkar';

  @override
  String get archiveExtracting => 'Arşiv çıkarılıyor…';

  @override
  String get archiveExtractComplete => 'Arşiv çıkarıldı';

  @override
  String archiveExtractFailed(String error) => 'Çıkarma başarısız: $error';

  @override
  String get archiveEmpty => 'Bu arşiv boş';

  @override
  String archivePreviewSummary(int count) => '$count öğe';

  @override
  String archivePreviewMore(int count) => '… ve $count tane daha';

  @override
  String get previewUnavailable => 'Önizleme kullanılamıyor';

  @override
  String get previewTextTruncated => 'Kısmi içerik gösteriliyor';

  @override
  String get previewTextTooLarge => 'Dosya önizleme için çok büyük';

  @override
  String get showPreview => 'Önizlemeyi göster';

  @override
  String get hidePreview => 'Önizlemeyi gizle';

  // Column names
  @override
  String get columnName => 'Ad';

  @override
  String get columnSize => 'Boyut';

  @override
  String get columnType => 'Tür';

  @override
  String get columnDateModified => 'Değiştirilme tarihi';

  @override
  String get columnDateCreated => 'Oluşturulma tarihi';

  @override
  String get columnAttributes => 'Öznitelikler';

  @override
  String get columnDateAccessed => 'Erişim tarihi';

  @override
  String get columnExtension => 'Uzantı';

  @override
  String get columnPath => 'Yol';

  @override
  String get columnTags => 'Etiketler';

  @override
  String get columnDimensions => 'Boyutlar';

  @override
  String get columnDuration => 'Süre';

  @override
  String get columnItemCount => 'Öğe sayısı';

  // Column descriptions
  @override
  String get columnSizeDescription => 'Dosya boyutunu göster';

  @override
  String get columnTypeDescription => 'Dosya türünü göster (PDF, Word vb.)';

  @override
  String get columnDateModifiedDescription =>
      'Dosyanın değiştirilme tarih ve saatini göster';

  @override
  String get columnDateCreatedDescription =>
      'Dosyanın oluşturulma tarih ve saatini göster';

  @override
  String get columnAttributesDescription =>
      'Dosya özniteliklerini göster (okuma/yazma izinleri)';

  @override
  String get columnDateAccessedDescription =>
      'Dosyaya son erişim tarih ve saatini göster';

  @override
  String get columnExtensionDescription =>
      'Dosya uzantısını göster (ör. .mp4, .docx)';

  @override
  String get columnPathDescription => 'Göreli dosya yolunu göster';

  @override
  String get columnTagsDescription => 'Dosya etiketlerini göster';

  @override
  String get columnDimensionsDescription =>
      'Görsel/video boyutlarını göster (genişlik x yükseklik)';

  @override
  String get columnDurationDescription =>
      'Video/ses dosyaları için medya süresini göster';

  @override
  String get columnItemCountDescription =>
      'Klasörlerin içindeki öğe sayısını göster';

  @override
  String get columnParentFolder => 'Klasör';

  @override
  String get columnPermissions => 'İzinler';

  @override
  String get columnParentFolderDescription => 'Öğeyi içeren klasörü göster';

  @override
  String get columnPermissionsDescription =>
      'Okuma/yazma/çalıştırma izinlerini göster (rwx)';

  @override
  String get columnResetLayout => 'Sütun sırasını ve genişliklerini sıfırla';

  // Column chooser
  @override
  String get columnChooserSubtitle =>
      'Gösterilecek sütunları işaretleyin. Sıralamak için gösterilen sütunları sürükleyin.';

  @override
  String get columnChooserSearchHint => 'Sütun ara';

  @override
  String get columnChooserAvailable => 'Kullanılabilir sütunlar';

  @override
  String columnChooserShown(int count) => 'Gösterilen ($count)';

  @override
  String get columnChooserBasicGroup => 'Temel';

  @override
  String get columnChooserCollectionGroup => 'Bu koleksiyon';

  @override
  String get columnChooserSystemGroup => 'Windows özellikleri';

  @override
  String get columnChooserSystemNote =>
      'Temel sütunlardan sonra gösterilir; bunlara göre sıralama henüz desteklenmiyor.';

  @override
  String get columnChooserLoadingSystem => 'Windows özellikleri yükleniyor…';

  @override
  String get columnChooserNoMatch => 'Eşleşen sütun yok';

  @override
  String get columnChooserAlwaysShown => 'Her zaman gösterilir';

  @override
  String get columnChooserHide => 'Sütunu gizle';

  // Column visibility dialog
  @override
  String get columnVisibilityInstructions =>
      'Ayrıntılar görünümünde göstermek istediğiniz sütunları seçin. "Ad" sütunu her zaman gösterilir ve devre dışı bırakılamaz. '
      'Taşımak için sütun başlığını, boyutlandırmak için kenarını sürükleyin; sıralamak için başlığa tıklayın.';

  // List field visibility
  @override
  String get listFieldVisibilityTitle => 'Liste alanlarını özelleştir';

  @override
  String get listFieldVisibilityInstructions =>
      'Liste görünümünde göstermek istediğiniz alanları seçin.';

  // Metadata format strings
  @override
  String dimensionsFormat(int width, int height) => '$width × $height';

  @override
  String itemCountFormat(int count) => '$count öğe';

  // Grid size dialog
  @override
  String gridSizeLabel(int count) => 'Öğe boyutu düzeyi: $count';

  @override
  String get gridSizeInstructions =>
      'Öğe boyutunu ayarlamak için kaydırıcıyı hareket ettirin';

  // More options menu
  @override
  String get selectMultipleFiles => 'Birden çok dosya seç';

  @override
  String get selectMultipleTags => 'Birden çok etiket seç';

  @override
  String get viewImageGallery => 'Görsel galerisini görüntüle';

  @override
  String get viewVideoGallery => 'Video galerisini görüntüle';

  // Navigation
  @override
  String get home => 'Ana Sayfa';
  @override
  String get back => 'Geri';
  @override
  String get forward => 'İleri';
  @override
  String get refresh => 'Yenile';
  @override
  String get parentFolder => 'Üst klasör';
  @override
  String get local => 'Yerel';
  @override
  String get networks => 'Ağlar';

  // File types
  @override
  String get image => 'Görsel';
  @override
  String get video => 'Video';
  @override
  String get audio => 'Ses';
  @override
  String get document => 'Belge';
  @override
  String get folder => 'Klasör';
  @override
  String get file => 'Dosya';

  // File type labels
  @override
  String get fileTypeGeneric => 'Dosya';
  @override
  String get fileTypeJpeg => 'JPEG görseli';
  @override
  String get fileTypePng => 'PNG görseli';
  @override
  String get fileTypeGif => 'GIF görseli';
  @override
  String get fileTypeBmp => 'BMP görseli';
  @override
  String get fileTypeTiff => 'TIFF görseli';
  @override
  String get fileTypeWebp => 'WebP görseli';
  @override
  String get fileTypeSvg => 'SVG görseli';
  @override
  String get fileTypeMp4 => 'MP4 videosu';
  @override
  String get fileTypeAvi => 'AVI videosu';
  @override
  String get fileTypeMov => 'MOV videosu';
  @override
  String get fileTypeWmv => 'WMV videosu';
  @override
  String get fileTypeFlv => 'FLV videosu';
  @override
  String get fileTypeMkv => 'MKV videosu';
  @override
  String get fileTypeMp3 => 'MP3 sesi';
  @override
  String get fileTypeWav => 'WAV sesi';
  @override
  String get fileTypeAac => 'AAC sesi';
  @override
  String get fileTypeFlac => 'FLAC sesi';
  @override
  String get fileTypeOgg => 'OGG sesi';
  @override
  String get fileTypePdf => 'PDF belgesi';
  @override
  String get fileTypeWord => 'Word belgesi';
  @override
  String get fileTypeExcel => 'Excel çalışma sayfası';
  @override
  String get fileTypePowerPoint => 'PowerPoint sunusu';
  @override
  String get fileTypeTxt => 'Metin dosyası';
  @override
  String get fileTypeRtf => 'RTF belgesi';
  @override
  String get fileTypeZip => 'ZIP arşivi';
  @override
  String get fileTypeRar => 'RAR arşivi';
  @override
  String get fileType7z => '7Z arşivi';
  @override
  String fileTypeWithExtension(String extension) => '$extension dosyası';

  // File template type names
  @override
  String get fileTypeMarkdown => 'Markdown';
  @override
  String get fileTypeJson => 'JSON dosyası';
  @override
  String get fileTypeHtml => 'HTML belgesi';
  @override
  String get fileTypeCss => 'CSS stil sayfası';
  @override
  String get fileTypeDart => 'Dart dosyası';
  @override
  String get fileTypePython => 'Python betiği';
  @override
  String get fileTypeJavaScript => 'JavaScript';
  @override
  String get fileTypeTypeScript => 'TypeScript';
  @override
  String get fileTypeJava => 'Java dosyası';
  @override
  String get fileTypeCpp => 'C++ dosyası';
  @override
  String get fileTypeC => 'C dosyası';
  @override
  String get fileTypeGo => 'Go dosyası';
  @override
  String get fileTypeRust => 'Rust dosyası';
  @override
  String get fileTypeXml => 'XML dosyası';
  @override
  String get fileTypeYaml => 'YAML dosyası';
  @override
  String get fileTypeShell => 'Kabuk betiği';
  @override
  String get fileTypeCsv => 'CSV çalışma sayfası';
  @override
  String get fileTypeLibreDoc => 'LibreOffice belgesi';
  @override
  String get fileTypeLibreSheet => 'LibreOffice çalışma sayfası';
  @override
  String get fileTypeLibrePresentation => 'LibreOffice sunusu';
  @override
  String get fileTypeLibreDraw => 'LibreOffice çizimi';
  @override
  String get fileTypeLibreChart => 'LibreOffice grafiği';
  @override
  String get fileTypeLibreFormula => 'LibreOffice formülü';
  @override
  String get fileTypeWpsDoc => 'WPS belgesi';
  @override
  String get fileTypeWpsSheet => 'WPS çalışma sayfası';
  @override
  String get fileTypeWpsPresentation => 'WPS sunusu';
  @override
  String get fileTypeGoogleDoc => 'Google Dokümanlar';
  @override
  String get fileTypeGoogleSheet => 'Google E-Tablolar';
  @override
  String get fileTypeGoogleSlides => 'Google Slaytlar';
  @override
  String get fileTypeTar => 'TAR arşivi';
  @override
  String get fileTypeGzip => 'GZIP arşivi';

  // Settings
  @override
  String get language => 'Dil';
  @override
  String get theme => 'Tema';
  @override
  String get darkMode => 'Koyu mod';
  @override
  String get lightMode => 'Açık mod';
  @override
  String get systemMode => 'Sistem modu';
  @override
  String get selectLanguage => 'Kullanmak istediğiniz dili seçin';
  @override
  String get selectTheme => 'Uygulamanın görünüm temasını seçin';
  @override
  String get selectThumbnailPosition =>
      'Video küçük resmi çıkarma konumunu seçin';
  @override
  String get systemThemeDescription => 'Sistem tema ayarlarını izle';
  @override
  String get lightThemeDescription => 'Tüm ekranlar için açık arayüz';
  @override
  String get darkThemeDescription => 'Tüm ekranlar için koyu arayüz';
  @override
  String get themeOnboardingTitle => 'Temanızı seçin';
  @override
  String get themeOnboardingDescription =>
      'Uygulamaya girmeden önce varsayılan görünümünüzü seçin.';
  @override
  String get themeOnboardingLightLabel => 'Açık';
  @override
  String get themeOnboardingDarkLabel => 'Koyu';
  @override
  String get themeOnboardingMoreThemesMessage =>
      'Daha fazla tema Ayarlar\'da mevcut.';
  @override
  String get themeOnboardingContinue => 'Devam';
  @override
  String get accentColor => 'Vurgu rengi';
  @override
  String currentAccentColor(String name) => 'Geçerli vurgu: $name';
  @override
  String get fontColor => 'Yazı rengi';
  @override
  String currentFontColor(String name) => 'Geçerli yazı rengi: $name';
  @override
  String get uiFont => 'Yazı tipi ailesi';
  @override
  String currentUiFont(String name) => 'Geçerli yazı tipi: $name';
  @override
  String get uiFontUnicodeHint =>
      'Ücretsiz Unicode yazı tipleri (Vietnamca + Genişletilmiş Latin). Ek yazı tipleri bir kez indirilir ve yerel olarak önbelleğe alınır.';
  @override
  String get backdropMode => 'Arka plan modu';
  @override
  String get backdropModeDynamic => 'Dinamik';
  @override
  String get backdropModeWallpaper => 'Duvar kağıdı';
  @override
  String get backdropModeDynamicDescription =>
      'Sistemin dinamik akrilik arka planı kullanılıyor.';
  @override
  String get backdropModeWallpaperDescription =>
      'Sistem duvar kağıdı arka plan olarak kullanılıyor.';
  @override
  String get noSystemWallpaperDetected => 'Sistem duvar kağıdı algılanamadı';
  @override
  String get customBackdropImage => 'Özel';
  @override
  String get backdropImageNotFound => 'Görsel bulunamadı';
  @override
  String get backdropModeGlass => 'Cam';
  @override
  String get backdropModeGlassDescription =>
      'macOS camı üzerinden uygulamanın arkasındaki masaüstünü ve pencereleri görün.';
  @override
  String get desktopGlassStrength => 'Cam saydamlığı';
  @override
  String desktopGlassStrengthDescription(int percentage) =>
      'Metnin arkasındaki koruyucu tonu koruyarak arka planı gösterin (%$percentage).';
  @override
  String get desktopGlassBlur => 'Cam arka plan bulanıklığı';
  @override
  String desktopGlassBlurDescription(int percentage) =>
      'Cam yüzeylerin arkasındaki duvar kağıdını ve içeriği yumuşatın (%$percentage).';
  @override
  String get desktopAcrylicStrength => 'Masaüstü akrilik yoğunluğu';
  @override
  String desktopAcrylicStrengthDescription(int percentage) =>
      'Masaüstü arka planı için bulanıklık ve ton yoğunluğunu ayarlayın (%$percentage).';
  @override
  String get vietnameseLanguage => 'Vietnamca';
  @override
  String get englishLanguage => 'İngilizce';
  @override
  String get turkishLanguage => 'Türkçe';
  @override
  String get chineseLanguage => 'Çince (Basitleştirilmiş)';
  @override
  String get languageOnboardingTitle => 'Dilinizi seçin';
  @override
  String get languageOnboardingDescription =>
      'CB File Hub\'ın kullanacağı dili seçin. Daha sonra Ayarlar\'dan değiştirebilirsiniz.';

  // Messages
  @override
  String get fileDeleteConfirmation =>
      'Bu dosyayı silmek istediğinizden emin misiniz?';
  @override
  String get folderDeleteConfirmation =>
      'Bu klasörü ve tüm içeriğini silmek istediğinizden emin misiniz?';
  @override
  String get fileDeleteSuccess => 'Dosya başarıyla silindi';
  @override
  String get folderDeleteSuccess => 'Klasör başarıyla silindi';
  @override
  String get operationFailed => 'İşlem başarısız';
  @override
  String get failedToCreateAlbum => 'Albüm oluşturulamadı';
  @override
  String get failedToUpdateAlbum => 'Albüm güncellenemedi';

  // Tags
  @override
  String get tags => 'Etiketler';
  @override
  String get addTag => 'Etiket ekle';
  @override
  String get removeTag => 'Etiketi kaldır';
  @override
  String get tagListRefreshing => 'Etiket listesi yenileniyor...';
  @override
  String get tagManagement => 'Etiket yönetimi';
  @override
  String get parentTagLabel => 'Üst';
  @override
  String get childTagInputHint => 'Alt etiket yazın…';
  @override
  String get copyTags => 'Etiketleri kopyala';
  @override
  String exitTagScope(String parent) => '"$parent" etiketinden çık';
  @override
  String childTagHint(String parent) => '"$parent" içinde yeni etiket...';
  @override
  String addingUnderTag(String parent) =>
      '"$parent" etiketine alt etiketler ekleniyor. Esc bu üst etiketten çıkar.';
  @override
  String get tagInputHelp =>
      'Bir üst etiket yazın, ardından çipinin içine alt etiket girmek için ":" veya → tuşuna basın.';
  @override
  String get tagSuggestionsLabel => 'Önerilen etiketler';
  @override
  String childTagCount(int count) => '$count alt etiket';
  @override
  String deleteTagConfirmation(String tag) => '"$tag" etiketi silinsin mi?';
  @override
  String get tagDeleteConfirmationText =>
      'Bu işlem etiketi tüm dosyalardan kaldırır. Bu işlem geri alınamaz.';
  @override
  String tagDeleted(String tag) => '"$tag" etiketi başarıyla silindi';
  @override
  String errorDeletingTag(String error) => 'Etiket silinirken hata: $error';
  @override
  String chooseTagColor(String tag) => '"$tag" için renk seçin';
  @override
  String tagColorUpdated(String tag) => '"$tag" etiketinin rengi güncellendi';
  @override
  String get allTags => 'Tüm etiketler';
  @override
  String get filesWithTag => '"%s" etiketli dosyalar';
  @override
  String get tagsInDirectory => '"%s" içindeki etiketler';
  @override
  String get aboutTags => 'Etiket yönetimi hakkında';
  @override
  String get aboutTagsTitle => 'Etiket yönetimine giriş:';
  @override
  String get aboutTagsDescription =>
      'Etiketler, özel etiketler ekleyerek dosyalarınızı düzenlemenize yardımcı olur. '
      'Dosyalara etiket ekleyip kaldırabilir ve belirli etiketlere sahip tüm dosyaları bulabilirsiniz.';
  @override
  String get aboutTagsScreenDescription =>
      '• Kütüphanenizdeki tüm etiketler\n'
      '• Seçilen etiketle etiketlenmiş dosyalar\n'
      '• Etiketleri silme seçenekleri';
  @override
  String get deleteTag => 'Bu etiketi tüm dosyalardan sil';
  @override
  String get deleteAlbum => 'Albümü sil';

  // Tag Management Screen
  @override
  String get tagManagementTitle => 'Etiket yönetimi';
  @override
  String get debugTags => 'Etiketlerde hata ayıkla';
  @override
  String get searchTags => 'Ara';
  @override
  String get searchTagsHint => 'Etiket ara...';
  @override
  String get createNewTag => 'Yeni etiket oluştur';
  @override
  String get newTagTooltip => 'Yeni etiket oluştur';
  @override
  String get errorLoadingTags => 'Etiketler yüklenirken hata: ';
  @override
  String get noTagsFoundMessage => 'Etiket bulunamadı';
  @override
  String get noTagsFoundDescription =>
      'Dosyaları düzenlemeye başlamak için yeni etiketler oluşturun';
  @override
  String get createNewTagButton => 'Yeni etiket oluştur';
  @override
  String noMatchingTagsMessage(String searchTags) =>
      '"$searchTags" ile eşleşen etiket yok';
  @override
  String get clearSearch => 'Aramayı temizle';
  @override
  String get tagManagementHeader => 'Etiket yönetimi';
  @override
  String get tagsCreated => 'etiket oluşturuldu';
  @override
  String get tagManagementDescription =>
      'Bir etikete dokunarak o etikete sahip tüm dosyaları görüntüleyin. Rengi değiştirmek veya etiketleri silmek için sağdaki düğmeleri kullanın.';
  @override
  String get sortTags => 'Etiketleri sırala';
  @override
  String get sortByAlphabet => 'Alfabetik';
  @override
  String get sortByPopular => 'Popülerliğe göre';
  @override
  String get listViewMode => 'Liste modu';
  @override
  String get gridViewMode => 'Izgara modu';
  @override
  String get treeViewMode => 'Ağaç modu';
  @override
  String get previousPage => 'Önceki sayfa';
  @override
  String get nextPage => 'Sonraki sayfa';
  @override
  String get page => 'Sayfa';
  @override
  String get firstPage => 'İlk sayfa';
  @override
  String get lastPage => 'Son sayfa';
  @override
  String get clickToViewFiles => 'Dosyaları görmek için dokunun';
  @override
  String get changeTagColor => 'Etiket rengini değiştir';
  @override
  String get deleteTagFromAllFiles => 'Bu etiketi tüm dosyalardan sil';
  @override
  String get openInNewTab => 'Yeni sekmede aç';
  @override
  String get viewFilesWithTag => 'Etiketli dosyaları görüntüle';
  @override
  String get setThumbnail => 'Küçük resim ayarla';
  @override
  String get removeThumbnail => 'Küçük resmi kaldır';
  @override
  String get manageHierarchy => 'Hiyerarşiyi yönet';
  @override
  String get renameTag => 'Etiketi yeniden adlandır';
  @override
  String tagRenamed(String oldTag, String newTag) =>
      '"$oldTag" etiketi "$newTag" olarak yeniden adlandırıldı';
  @override
  String get openInSplitView => 'Bölünmüş görünümde aç';
  @override
  String get changeColor => 'Rengi değiştir';
  @override
  String get noFilesWithTag => 'Bu etikete sahip dosya bulunamadı';
  @override
  String debugInfo(String tag) =>
      'Hata ayıklama bilgisi: "$tag" etiketi aranıyor';
  @override
  String get backToAllTags => 'Tüm etiketlere dön';
  @override
  String get tryAgain => 'Tekrar dene';
  @override
  String get filesWithTagCount => 'dosya';
  @override
  String get viewDetails => 'Ayrıntıları görüntüle';
  @override
  String get openContainingFolder => 'Bulunduğu klasörü aç';
  @override
  String get editTags => 'Etiketleri düzenle';
  @override
  String get newTagTitle => 'Yeni etiket oluştur';
  @override
  String get enterTagName => 'Etiket adını girin...';
  @override
  String get tagName => 'Etiket adı';
  @override
  String get enterNewTagName => 'Yeni etiket adını girin...';
  @override
  String tagAlreadyExists(String tagName) => '"$tagName" etiketi zaten mevcut';
  @override
  String tagCreatedSuccessfully(String tagName) =>
      '"$tagName" etiketi başarıyla oluşturuldu';
  @override
  String get errorCreatingTag => 'Etiket oluşturulurken hata: ';
  @override
  String get tagsSavedSuccessfully => 'Etiketler başarıyla kaydedildi';
  @override
  String get selectTagToRemove => 'Kaldırılacak bir etiket seçin:';
  @override
  String get selectFilesToRemoveTags =>
      'Etiketleri kaldırmak için lütfen dosyaları seçin';
  @override
  String get doubleClickToRename => 'Yeniden adlandırmak için çift tıklayın';
  @override
  String get openingFolder => 'Klasör açılıyor: ';
  @override
  String get folderNotFound => 'Klasör bulunamadı: ';
  @override
  String get refreshTags => 'Etiketleri yenile';
  @override
  String tagsRefreshed(int count) =>
      'Etiketler yenilendi - $count etiket yüklendi';
  @override
  String get tagManagementInfoTitle => 'Etiket yönetimi bilgisi';
  @override
  String get tagManagementInfoDescription =>
      'Bu ekran, dosya ve klasörlerin etiketlerini yönetmenizi sağlar.\n\n'
      '• Tüm etiketleri görüntüleyin\n'
      '• Etiketleri arayın\n'
      '• Etiketleri ada veya popülerliğe göre sıralayın\n'
      '• Bir etikete atanmış dosyaları görüntüleyin';
  @override
  String removeTagsFromFilesTitle(int count) =>
      '$count dosyadan etiketleri kaldır';
  @override
  String get loadingTags => 'Etiketler yükleniyor...';
  @override
  String get noCommonTagsAcrossSelectedFiles =>
      'Seçilen dosyalar arasında ortak etiket yok';
  @override
  String removeTagsSuccess(int removedTagCount, int fileCount) =>
      '$fileCount dosyadan $removedTagCount etiket kaldırıldı';
  @override
  String removeTagsError(String error) =>
      'Etiketler kaldırılırken hata: $error';
  @override
  String batchTagProcessingError(String error) =>
      'Etiketler işlenirken hata: $error';
  @override
  String searchError(String error) => 'Arama hatası: $error';

  // Gallery
  @override
  String get imageGallery => 'Görsel galerisi';
  @override
  String get videoGallery => 'Video galerisi';

  // Additional translations for database settings
  @override
  String get databaseSettings => 'Veritabanı ayarları';
  @override
  String get databaseStorage => 'Veritabanı depolama';
  @override
  String get useDatabaseStorage => 'SQLite veritabanını kullan';
  @override
  String get databaseStorageEnabled =>
      'Verimli yerel veritabanı depolaması için SQLite kullanılıyor';
  @override
  String get databaseDescription =>
      'Etiketleri ve tercihleri yerel bir veritabanında sakla';
  @override
  String get jsonStorage => 'Temel depolama için JSON dosyası kullanılıyor';
  @override
  String get objectBoxStorage =>
      'Verimli yerel veritabanı depolaması için SQLite kullanılıyor'; // Legacy

  // Cloud sync
  @override
  String get cloudSync => 'Bulut senkronizasyonu';
  @override
  String get enableCloudSync => 'Bulut senkronizasyonunu etkinleştir';
  @override
  String get cloudSyncDescription =>
      'Etiketleri ve tercihleri buluta senkronize et';
  @override
  String get syncToCloud => 'Buluta senkronize et';
  @override
  String get syncFromCloud => 'Buluttan senkronize et';
  @override
  String get cloudSyncEnabled =>
      'Etiketler ve tercihler buluta senkronize edilecek';
  @override
  String get cloudSyncDisabled => 'Bulut senkronizasyonu devre dışı';
  @override
  String get syncToCloudSuccess => 'Buluta başarıyla senkronize edildi';
  @override
  String get syncToCloudFailed => 'Buluta senkronize edilemedi';
  @override
  String get syncFromCloudSuccess => 'Buluttan başarıyla senkronize edildi';
  @override
  String get syncFromCloudFailed => 'Buluttan senkronize edilemedi';
  @override
  String get enableDatabaseForCloud =>
      'Bulut senkronizasyonunu kullanmak için SQLite veritabanını etkinleştirin';
  @override
  String get backupAndSync => 'Yedekleme ve senkronizasyon';
  @override
  String get chooseCloudSyncFolder => 'Senkronizasyon klasörünü seç';
  @override
  String get cloudBackupNotFound => 'Bulut yedeği bulunamadı';
  @override
  String get cloudProvider => 'Bulut hizmeti';
  @override
  String get cloudProviderNotConfigured =>
      'Bu sürümde kullanılamıyor (derlemeye OAuth istemci kimliği eklenmemiş)';
  @override
  String get localSyncFolder => 'Yerel senkronizasyon klasörü';
  @override
  String get localSyncFolderDescription =>
      'Arşivi, masaüstü senkronizasyon uygulamanızın zaten yansıttığı bir klasöre yazın';
  @override
  String get openingBrowserToSignIn => 'Oturum açmak için tarayıcı açılıyor...';
  @override
  String connectedAsAccount(String account) => '$account olarak bağlanıldı';
  @override
  String cloudBackupsStoredIn(String folder) =>
      'Yedekler $folder içinde saklanır';
  @override
  String get chooseBackupToRestore => 'Geri yüklenecek bir yedek seçin';
  @override
  String get noCloudBackupsYet => 'Bu sürücüde henüz yedek yok';
  @override
  String get uploadingBackup => 'Yedek yükleniyor...';
  @override
  String get downloadingBackup => 'Yedek indiriliyor...';
  @override
  String backupUploadedTo(String provider) =>
      'Yedek $provider hizmetine yüklendi';
  @override
  String get deleteCloudBackupConfirm =>
      'Bu yedek bulut sürücüsünden silinsin mi?';
  @override
  String get connectCloudFirst => 'Önce bulut hizmetine bağlanın';
  @override
  String get syncAllClouds => 'Bağlı tüm sürücülere yedekle';
  @override
  String cloudConnectedCount(int connected, int total) =>
      '$total sürücüden $connected tanesi bağlı';
  @override
  String get cloudStatusConnected => 'Bağlı';
  @override
  String get cloudStatusUnavailable => 'Kullanılamıyor';
  @override
  String get cloudStatusFailed => 'Başarısız';
  @override
  String get waitingForSignIn => 'Tarayıcıda oturum açılması bekleniyor...';
  @override
  String lastBackupAt(String time) => 'Son yedekleme: $time';
  @override
  String lastBackupFailedAt(String time, String error) =>
      'Yedekleme başarısız ($time): $error';
  @override
  String get neverBackedUpHere => 'Bu cihazdan henüz yedeklenmedi';
  @override
  String syncAllResult(int succeeded, int total) =>
      '$total sürücüden $succeeded tanesine yedeklendi';
  @override
  String get backUpNow => 'Yedekle';
  @override
  String get restoreBackup => 'Geri yükle';

  // Database statistics
  @override
  String get databaseStatistics => 'Veritabanı istatistikleri';
  @override
  String get totalUniqueTags => 'Toplam benzersiz etiket';
  @override
  String get taggedFiles => 'Etiketli dosyalar';
  @override
  String get popularTags => 'En popüler etiketler';
  @override
  String get recentTags => 'Son etiketler';
  @override
  String get selectedTags => 'Seçilen etiketler:';
  @override
  String batchAddTags(int count) => '$count dosyaya etiket ekle';
  @override
  String get applyingChanges => 'Değişiklikler uygulanıyor...';
  @override
  String tagsUpdated(int count, int added, int removed) {
    var msg = '$count dosya için etiketler güncellendi';
    final parts = <String>[];
    if (added > 0) parts.add('$added eklendi');
    if (removed > 0) parts.add('$removed kaldırıldı');
    if (parts.isNotEmpty) msg += ' (${parts.join(', ')})';
    return msg;
  }

  @override
  String get tagSuggestions => 'Etiket önerileri';
  @override
  String get advancedDatabaseSettings => 'Gelişmiş veritabanı ayarları';
  @override
  String get noTagsFound => 'Etiket bulunamadı';
  @override
  String get refreshStatistics => 'İstatistikleri yenile';

  // Raw Data Viewer
  @override
  String get viewRawData => 'Ham veriyi görüntüle';
  @override
  String get rawDataPreferences => 'Tercihler';
  @override
  String get rawDataTags => 'Dosya etiketleri';
  @override
  String get rawDataDescription =>
      'Veritabanında saklanan ham veriyi görüntüleyin (hata ayıklama için)';
  @override
  String get noDataFound => 'Veri bulunamadı';

  // Import/Export
  @override
  String get importExportDatabase => 'Veritabanını içe/dışa aktar';
  @override
  String get backupRestoreDescription =>
      'Etiketlerinizi ve dosya ilişkilerinizi yedekleyin ve geri yükleyin';
  @override
  String get exportDatabase => 'Veritabanını dışa aktar';
  @override
  String get exportSettings => 'Ayarları dışa aktar';
  @override
  String get importDatabase => 'Veritabanını içe aktar';
  @override
  String get importSettings => 'Ayarları içe aktar';
  @override
  String get resetSettings => 'Ayarları sıfırla';
  @override
  String get exportDescription => 'Etiketlerinizi bir dosyaya kaydedin';
  @override
  String get importDescription => 'Etiketlerinizi bir dosyadan geri yükleyin';
  @override
  String get completeBackup => 'Tam yedekleme';
  @override
  String get completeRestore => 'Tam geri yükleme';
  @override
  String get exportAllData =>
      'Tüm ayarları ve veritabanı verilerini dışa aktar';
  @override
  String get importAllData => 'Tüm ayarları ve veritabanı verilerini içe aktar';

  // Export/Import messages
  @override
  String get exportSuccess => 'Başarıyla dışa aktarıldı: ';
  @override
  String get exportFailed => 'Dışa aktarma başarısız';
  @override
  String get importSuccess => 'Başarıyla içe aktarıldı';
  @override
  String get importFailed => 'İçe aktarma başarısız oldu veya iptal edildi';
  @override
  String get importCancelled => 'İçe aktarma iptal edildi';
  @override
  String get errorExporting => 'Dışa aktarma hatası: ';
  @override
  String get errorImporting => 'İçe aktarma hatası: ';
  @override
  String get backupAndRestore => 'Yedekleme ve geri yükleme';
  @override
  String get backupRestoreHint =>
      'Etiketleri ve tercihleri bir .db dosyasına yedekleyin (hızlı, ölçeklenebilir) veya tercihleri JSON olarak dışa aktarın (okunabilir).';
  @override
  String get exportSqlite => 'SQLite dışa aktar';
  @override
  String get exportSqliteDesc =>
      'Hızlı yedekleme (.db) — etiketler + tercihler';
  @override
  String get exportJson => 'JSON dışa aktar';
  @override
  String get exportJsonDesc => 'Tercihleri okunabilir JSON olarak dışa aktar';
  @override
  String get importBackup => 'Yedeği içe aktar';
  @override
  String get importBackupDesc => '.db veya .json dosyasını otomatik algılar';
  @override
  String get exporting => 'Dışa aktarılıyor...';
  @override
  String get importing => 'İçe aktarılıyor...';
  @override
  String get sharedPreferences => 'SharedPreferences';
  @override
  String get sharedPreferencesDesc =>
      'Uygulama anahtar-değer ayarlarını görüntüleyin ve temizleyin';
  @override
  String get clearSharedPreferencesConfirm =>
      'Tüm SharedPreferences temizlensin mi?';
  @override
  String get deleteKeyConfirm => 'Bu anahtar silinsin mi?';
  @override
  String get clear => 'Temizle';
  @override
  String get sharedPreferencesCleared => 'SharedPreferences temizlendi.';
  @override
  String get deletedKey => 'Silindi: ';
  @override
  String get copied => 'Kopyalandı: ';
  @override
  String tagsImported(int count) => '$count etiket içe aktarıldı';
  @override
  String settingsRestored(int count) => '$count ayar geri yüklendi';
  @override
  String get saveBackup => 'Yedeği kaydet';
  @override
  String get exportPreferencesAsJson => 'Tercihleri JSON olarak dışa aktar';
  @override
  String get exportBackupZip => 'Yedeği ZIP olarak dışa aktar';
  @override
  String get exportBackupZipDesc =>
      'Dahil edilecek ayarları ve etiketleri seçin';
  @override
  String get importBackupZip => 'ZIP yedeğini içe aktar';
  @override
  String get importBackupZipDesc => 'Hangi bölümlerin geri yükleneceğini seçin';
  @override
  String get backupSettingsPart => 'Ayarlar';
  @override
  String get backupTagsPart => 'Etiketler';
  @override
  String get continueText => 'Devam';
  @override
  String get sharedPreferencesKeyRemoved =>
      'Ayar SharedPreferences\'tan kaldırıldı.';
  @override
  String get jsonCopiedToClipboard => 'JSON panoya kopyalandı';
  @override
  String get copyValue => 'Değeri kopyala';
  @override
  String get deleteKey => 'Anahtarı sil';
  @override
  String get copyJson => 'JSON\'u kopyala';
  @override
  String get viewJson => 'JSON\'u görüntüle';
  @override
  String get clearAll => 'Tümünü temizle';

  // Video thumbnails
  @override
  String get videoThumbnails => 'Video küçük resimleri';
  @override
  String get thumbnailMode => 'Oluşturma modu';
  @override
  String get thumbnailModeFast => 'Hızlı';
  @override
  String get thumbnailModeCustom => 'Özel';
  @override
  String get thumbnailModeFastDescription =>
      'İşletim sisteminin yerleşik yöntemlerini kullanır. Daha hızlıdır ancak konum sabittir.';
  @override
  String get thumbnailModeCustomDescription =>
      'Belirli bir konumdan çıkarmak için FFmpeg kullanır. Daha yavaştır ancak daha fazla denetim sağlar.';
  @override
  String get thumbnailPosition => 'Küçük resim konumu:';
  @override
  String get generatingAtPosition => 'Şu konumdan çıkarılıyor:';
  @override
  String get generatingFast => 'Hızlı mod';
  @override
  String get maxConcurrency => 'En fazla paralel görev';
  @override
  String get maxConcurrencyDescription =>
      'Yüksek değerler küçük resimleri daha hızlı oluşturur ancak daha fazla CPU kullanır';
  @override
  String get percentOfVideo => 'videonun yüzdesi';
  @override
  String get thumbnailDescription =>
      'Küçük resimlerin çıkarılacağı videodaki konumu (toplam sürenin yüzdesi olarak) ayarlayın';
  @override
  String get useSystemDefaultForVideo =>
      'Video için sistem varsayılan uygulamasını kullan';
  @override
  String get useSystemDefaultForVideoDescription =>
      'Açıkken, bir videoya dokunmak onu sistem varsayılan uygulamasıyla açar. Kapalıyken uygulama içi oynatıcı kullanılır.';
  @override
  String get useSystemDefaultForVideoEnabled =>
      'Videolar sistem varsayılan uygulamasıyla açılacak';
  @override
  String get useSystemDefaultForVideoDisabled =>
      'Videolar uygulama içi oynatıcıda açılacak';
  @override
  String get seekSpeed => 'Atlama hızı';
  @override
  String get videoSeekAcceleration => 'Basılı tuttukça hızlan';
  @override
  String get videoSeekAccelerationDescription =>
      'Atlama tuşunu ne kadar uzun basılı tutarsanız her atlama o kadar büyür. Kapalı: her atlama aynı adımı kullanır.';
  @override
  String get videoKeyboardSeekStep => 'Klavye atlama adımı';
  @override
  String get videoKeyboardSeekStepDescription =>
      'Sol/sağ tuşuna her basışta atlanan süre. Sürekli atlamak için tuşu basılı tutun.';
  @override
  String videoSeekSeconds(int seconds) => '$seconds sn';
  @override
  String get seekSpeedDescription =>
      'Atlama tuşunu basılı tutarken veya mobilde uzun basarken videonun ne kadar hızlı atladığı';
  @override
  String get seekSpeedSlow => 'Yavaş';
  @override
  String get seekSpeedMedium => 'Orta';
  @override
  String get seekSpeedFast => 'Hızlı';
  @override
  String get videoWheelAction => 'Video üzerinde fare tekerleği';
  @override
  String get videoWheelActionDescription =>
      'Oynatıcı üzerinde kaydırmanın yaptığı işlem. Değiştirmek için videoya orta tıklayın.';
  @override
  String get videoWheelVolume => 'Ses';
  @override
  String get videoWheelSeek => 'Atlama';
  @override
  String videoWheelModeSwitched(String mode) => 'Fare tekerleği: $mode';
  @override
  String videoWheelSwitchHint(String mode) =>
      '$mode moduna geçmek için orta tıklayın';
  @override
  String get videoDecoding => 'Video kod çözme';
  @override
  String get videoDecodingAuto => 'Otomatik (önerilen)';
  @override
  String get videoDecodingGpu => 'Her zaman GPU kullan';
  @override
  String get videoDecodingCpu => 'Her zaman CPU kullan';
  @override
  String get videoDecodingAutoDescription =>
      'Akıcı oynatma ve daha düşük pil kullanımı için bu cihazdaki yerleşik GPU kod çözücüyü kullanır. GPU başarısız olursa CPU\'ya geçer.';
  @override
  String get videoDecodingAutoDescriptionWindows =>
      'Çoğu video için CPU kullanır ve atlamanın akıcı kalması için 4K videolarda GPU\'ya geçer. GPU başarısız olursa CPU\'ya geçer.';
  @override
  String get videoDecodingGpuDescription =>
      'Tüm videoların kodunu ekran kartında çözer. CPU için en hafif seçenektir ancak bazı sürücüler başarısız olabilir; bu durumda oynatma CPU\'ya geçer.';
  @override
  String get videoDecodingCpuDescription =>
      'Her makinede çalışır ancak 4K videolarda atlama yavaştır ve daha fazla CPU kullanılır.';
  @override
  String get videoDecodingReopenHint =>
      'Bir sonraki video açılışında tamamen uygulanır.';
  @override
  String get videoDecodingFellBackToCpu =>
      "GPU bu videonun kodunu çözemedi, bu yüzden oynatma CPU'ya geçti. Bunu Video ayarlarından değiştirebilirsiniz.";
  @override
  String get openVideoInNewWindow => 'Videoları ayrı bir pencerede aç';
  @override
  String get openVideoInNewWindowDescription =>
      'Yalnızca masaüstü. Uygulama içi tek bir ayrı oynatıcı penceresi kullanır; başka bir video açmak o penceredeki geçerli videonun yerini alır.';
  @override
  String get openVideoInNewWindowEnabled =>
      'Videolar ayrı bir oynatıcı penceresinde açılacak';
  @override
  String get openVideoInNewWindowDisabled =>
      'Video oynatıcı geçerli pencerede açılacak';
  @override
  String get thumbnailCache => 'Küçük resim önbelleği';
  @override
  String get thumbnailCacheDescription =>
      'Performansı artırmak için video küçük resimleri önbelleğe alınır. Küçük resimler güncel görünmüyorsa veya yer açmak istiyorsanız önbelleği temizleyebilirsiniz.';
  @override
  String get clearThumbnailCache => 'Küçük resim önbelleğini temizle';
  @override
  String get clearing => 'Temizleniyor...';
  @override
  String get thumbnailCleared => 'Tüm video küçük resimleri temizlendi';
  @override
  String get errorClearingThumbnail => 'Küçük resimler temizlenirken hata: ';

  // New tab
  @override
  String get newTab => 'Yeni sekme';

  // Admin access
  @override
  String get adminAccess => 'Yönetici erişimi';
  @override
  String get adminAccessRequired =>
      'Bu sürücüye erişmek için yönetici ayrıcalıkları gerekir';
  @override
  String get requiresAdminPrivileges => 'Yönetici ayrıcalıkları gerektirir';
  @override
  String driveRequiresAdmin(String path) =>
      '$path sürücüsüne erişmek için yönetici ayrıcalıkları gerekir.';
  @override
  String get trashBin => 'Çöp kutusu';

  // File system
  @override
  String get drives => 'Sürücüler';
  @override
  String get system => 'Sistem';

  // Settings data
  @override
  String get settingsData => 'Ayar verileri';
  @override
  String get viewManageSettings => 'Ayar verilerini görüntüleyin ve yönetin';

  // About app
  @override
  String get aboutApp => 'Uygulama hakkında';
  @override
  String get appDescription => 'Gelişmiş bir dosya yönetimi çözümü';
  @override
  String get version => 'Sürüm';
  @override
  String get developer => 'Geliştirici';

  // Empty state
  @override
  String get emptyFolder => 'Boş klasör';
  @override
  String get noImagesFound => 'Bu klasörde görsel bulunamadı';
  @override
  String get noVideosFound => 'Bu klasörde video bulunamadı';
  @override
  String get loading => 'Yükleniyor...';

  // File picker dialogs
  @override
  String get chooseBackupLocation => 'Yedekleme konumunu seçin';
  @override
  String get chooseRestoreLocation => 'Geri yükleme dosyasını seçin';
  @override
  String get saveSettingsExport => 'Ayar dışa aktarımını kaydet';
  @override
  String get saveDatabaseExport => 'Veritabanı dışa aktarımını kaydet';
  @override
  String get selectBackupFolder => 'Yedekleme klasörünü seçin';

  // File details
  @override
  String get fileSize => 'Boyut';
  @override
  String get fileLocation => 'Konum';
  @override
  String get fileCreated => 'Oluşturulma';
  @override
  String get fileModified => 'Değiştirilme';
  @override
  String get fileName => 'Dosya adı';
  @override
  String get filePath => 'Dosya yolu';
  @override
  String get fileType => 'Dosya türü';
  @override
  String get fileLastModified => 'Son değiştirilme';
  @override
  String get fileAccessed => 'Erişim';
  @override
  String get loadingVideo => 'Video yükleniyor...';
  @override
  String get errorLoadingImage => 'Görsel yüklenirken hata';
  @override
  String errorLoadingImageWithError(String error) =>
      'Görsel yüklenirken hata: $error';
  @override
  String get failedToDisplayImage => 'Görsel görüntülenemedi';
  @override
  String get noImageDataAvailable => 'Görsel verisi yok';
  @override
  String get urlLoadingNotImplemented => 'URL yükleme henüz uygulanmadı';
  @override
  String get duration => 'Süre';
  @override
  String get resolution => 'Çözünürlük';
  @override
  String get createCopy => 'Kopya oluştur';
  @override
  String get deleteFile => 'Dosyayı sil';

  // Folder thumbnails
  @override
  String get folderThumbnail => 'Klasör küçük resmi';
  @override
  String get chooseThumbnail => 'Küçük resim seç';
  @override
  String get cropImage => 'Görseli kırp';
  @override
  String get applyCrop => 'Uygula';
  @override
  String get useOriginal => 'Orijinali kullan';
  @override
  String get aspectFree => 'Serbest';
  @override
  String get tagGridCropRecommendation =>
      'Etiket ızgarası kartları için önerilen: 16:9, en az 1280 × 720 px';
  @override
  String get tagGridAspectPreset => '16:9 · Etiket ızgarası';
  @override
  String get clearThumbnail => 'Küçük resmi temizle';
  @override
  String get thumbnailAuto => 'Otomatik (ilk video/görsel)';
  @override
  String get folderThumbnailSet => 'Klasör küçük resmi güncellendi';
  @override
  String get folderThumbnailCleared => 'Klasör küçük resmi temizlendi';
  @override
  String get invalidThumbnailFile =>
      'Lütfen bir görsel veya video dosyası seçin';
  @override
  String get noMediaFilesFound => 'Bu klasörde medya dosyası bulunamadı';

  // Video actions
  @override
  String get share => 'Paylaş';
  @override
  String get playVideo => 'Videoyu oynat';
  @override
  String get videoInfo => 'Video bilgisi';
  @override
  String get deleteVideo => 'Videoyu sil';
  @override
  String get loadingThumbnails => 'Küçük resimler yükleniyor';
  @override
  String get deleteVideosConfirm => 'Videolar silinsin mi?';
  @override
  String get deleteConfirmationMessage =>
      'Seçilen videoları silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  @override
  String videosSelected(int count) => '$count video seçildi';
  @override
  String videosDeleted(int count) => '$count video silindi';
  @override
  String searchingFor(String query) => 'Aranıyor: "$query"';
  @override
  String get errorDisplayingVideoInfo => 'Video bilgisi görüntülenemiyor';
  @override
  String get searchVideos => 'Video ara';
  @override
  String get enterVideoName => 'Video adını girin...';

  // Selection and grid
  @override
  String? get selectMultiple => 'Birden çok dosya seç';
  @override
  String? get gridSize => 'Izgara boyutu';

  @override
  String get searchOrEnterPath => 'Ara veya yol gir';

  @override
  String get pleaseCreateTabFirst => 'Lütfen önce bir sekme oluşturun';

  @override
  String get viewMode => 'Görünüm modu';

  @override
  String get masonryLayout => 'Mozaik düzen (Pinterest)';

  // Sorting
  @override
  String get sort => 'Sırala';
  @override
  String get sortByName => 'Ada göre sırala';
  @override
  String get sortByPopularity => 'Popülerliğe göre sırala';
  @override
  String get sortByRecent => 'Yakınlığa göre sırala';
  @override
  String get sortBySize => 'Boyuta göre sırala';
  @override
  String get sortByDate => 'Tarihe göre sırala';
  @override
  String get viewModeFeatureComingSoon =>
      'Görünüm modu geçişi daha sonra eklenecek';
  @override
  String get cannotCreateFileInThisLocation =>
      'Bu konumda dosya oluşturulamıyor';

  // Bulk Selection
  @override
  String get bulkSelect => 'Toplu seç';
  @override
  String get selectAllTags => 'Tümünü seç';
  @override
  String selectAllOnAllPages(int totalCount) =>
      'Tümünü seç ($totalCount etiket)';
  @override
  String get deselectAllTags => 'Tüm seçimi kaldır';
  @override
  String tagsSelected(int count) => '$count etiket seçildi';
  @override
  String bulkDeleteConfirmationTitle() => 'Seçilen etiketler silinsin mi?';
  @override
  String bulkDeleteConfirmationText(int count) =>
      '$count etiketi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  @override
  String bulkDeleteSuccess(int count) => '$count etiket başarıyla silindi';

  // Search errors
  @override
  String noFilesFoundTag(Map<String, String> args) =>
      '"${args['tag']}" etiketli dosya bulunamadı';

  @override
  String noFilesFoundTagGlobal(Map<String, String> args) =>
      '"${args['tag']}" etiketli dosya genel olarak bulunamadı';

  @override
  String noFilesFoundTags(Map<String, String> args) =>
      '${args['tags']} etiketli dosya bulunamadı';

  @override
  String noFilesFoundTagsGlobal(Map<String, String> args) =>
      '${args['tags']} etiketli dosya genel olarak bulunamadı';

  @override
  String noFilesFoundQuery(Map<String, String> args) =>
      '"${args['query']}" için sonuç bulunamadı';

  @override
  String errorSearchTag(Map<String, String> args) =>
      'Etikete göre arama hatası: ${args['error']}';

  @override
  String errorSearchTagGlobal(Map<String, String> args) =>
      'Etikete göre genel arama hatası: ${args['error']}';

  @override
  String errorSearchTags(Map<String, String> args) =>
      'Birden çok etikete göre arama hatası: ${args['error']}';

  @override
  String errorSearchTagsGlobal(Map<String, String> args) =>
      'Birden çok etikete göre genel arama hatası: ${args['error']}';

  // Search status
  @override
  String searchingTag(Map<String, String> args) =>
      '"${args['tag']}" etiketi aranıyor...';

  @override
  String searchingTagGlobal(Map<String, String> args) =>
      '"${args['tag']}" etiketi genel olarak aranıyor...';

  @override
  String searchingTags(Map<String, String> args) =>
      '${args['tags']} etiketleri aranıyor...';

  @override
  String searchingTagsGlobal(Map<String, String> args) =>
      '${args['tags']} etiketleri genel olarak aranıyor...';

  // Search UI
  @override
  String get searchTips => 'Arama ipuçları';

  @override
  String get searchTipsTitle => 'Arama ipuçları';

  @override
  String get viewTagSuggestions => 'Etiket önerilerini görüntüle';

  @override
  String get globalSearchModeEnabled => 'Alt klasör aramasına geçildi';

  @override
  String get localSearchModeEnabled => 'Geçerli klasör aramasına geçildi';

  @override
  String get globalSearchMode =>
      'Alt klasörlerde aranıyor (geçiş için dokunun)';

  @override
  String get localSearchMode =>
      'Geçerli klasörde aranıyor (geçiş için dokunun)';

  @override
  String get searchByFilename => 'Dosya adına göre ara';

  @override
  String get searchByTags => 'Etiketlere göre ara';

  @override
  String get searchMultipleTags => 'Birden çok etiket ara';

  @override
  String get globalSearch => 'Alt klasör araması';

  @override
  String get searchByNameOrTag => 'Ada veya #etikete göre ara';

  @override
  String get searchInSubfolders => 'Alt klasörlerde ara';

  @override
  String get featureNotImplemented => 'Bu özellik yakında eklenecek';

  @override
  String get searchInAllFolders => 'Geçerli klasörde ve alt klasörlerde ara';

  @override
  String get searchInCurrentFolder => 'Yalnızca geçerli klasörde ara';

  @override
  String get searchShortcuts => 'Kısayollar';

  @override
  String get regexMode => 'Regex modu';

  @override
  String get regexModeEnabled => 'Regex modu etkin';

  @override
  String get regexModeDisabled => 'Regex modu devre dışı';

  @override
  String get searchHintText =>
      'Dosya arayın veya etiketle aramak için # kullanın';

  @override
  String get searchHintTextTags => 'Etiketlere göre ara... (ör. #önemli #iş)';

  @override
  String get suggestedTags => 'Önerilen etiketler';

  @override
  String get noMatchingTags => 'Eşleşen etiket bulunamadı';

  @override
  String get results => 'sonuç';

  @override
  String searchResultsTitle(String countText) => 'Arama sonuçları$countText';

  @override
  String searchResultsTitleForQuery(String query, String countText) =>
      '"$query" için arama sonuçları$countText';

  @override
  String searchResultsTitleForTag(String tag, String countText) =>
      '"$tag" için etiket arama sonuçları$countText';

  @override
  String searchResultsTitleForTagGlobal(String tag, String countText) =>
      '"$tag" için genel etiket arama sonuçları$countText';

  @override
  String searchResultsTitleForFilter(String filter, String countText) =>
      '"$filter" için filtrelenmiş sonuçlar$countText';

  @override
  String searchResultsTitleForMedia(String mediaType, String countText) =>
      '$mediaType için arama sonuçları$countText';

  @override
  String get searchByFilenameDesc => 'Aramak için bir dosya adı girin.';

  @override
  String get searchByTagsDesc =>
      'Etikete göre aramak için # simgesini kullanın. Örnek: #önemli';

  @override
  String get searchMultipleTagsDesc =>
      'Sonuçları daha hassas filtrelemek için aynı anda birden çok etiket kullanın. Her etiketin başında # simgesi olmalı ve etiketler boşlukla ayrılmalıdır. Örnek: #iş #acil #2023';

  @override
  String get globalSearchDesc =>
      'Yalnızca geçerli klasörde arama ile alt klasörleri de kapsayan arama arasında geçiş yapmak için klasör/küre simgesine tıklayın.';

  @override
  String get regexSearchDesc =>
      'Adları düzenli ifadelerle eşleştirmek için regex modunu ({ }) etkinleştirin.\n'
      'Temel örnekler:\n'
      '• "img_" ile başlayan: ^img_.*\n'
      '• .mp4 ile biten: .*\\.mp4\$\n'
      '• "invoice" içeren: .*invoice.*\n'
      '• Tam 4 rakam: ^\\d{4}\$\n'
      '• Yıllı rapor: ^report_\\d{4}\\.pdf\$';

  @override
  String get searchShortcutsDesc =>
      'Aramayı başlatmak için Enter tuşuna basın. Önerilerden etiket seçmek için ok tuşlarını kullanın.';

  // File operations related to networks
  @override
  String get download => 'İndir';
  @override
  String get downloadFile => 'Dosyayı indir';
  @override
  String get selectDownloadLocation => 'Dosyanın kaydedileceği konumu seçin:';
  @override
  String get selectFolder => 'Klasör seç';
  @override
  String get browse => 'Gözat...';
  @override
  String get upload => 'Dosya yükle';
  @override
  String get uploadFile => 'Dosya yükle';
  @override
  String get selectFileToUpload => 'Yüklenecek dosyayı seçin:';
  @override
  String get create => 'Oluştur';
  @override
  String get folderName => 'Klasör adı';

  // Permissions
  @override
  String get grantPermissionsToContinue => 'Devam etmek için izin verin';

  @override
  String get permissionsDescription =>
      'Uygulamayı sorunsuz kullanmak için lütfen aşağıdaki izinleri verin. Atlayıp daha sonra Ayarlar\'dan verebilirsiniz.';

  @override
  String get storagePermissionRequiredMessage =>
      'Klasör içeriğini görüntülemek için tüm dosyalara erişim gerekir. Lütfen Ayarlar > Uygulamalar > CB File Hub > İzinler bölümüne gidin ve "Tüm dosyalara erişim" seçeneğini etkinleştirin.';

  @override
  String get storagePhotosPermission => 'Depolama/Fotoğraflar izni';

  @override
  String get storagePhotosDescription =>
      'Uygulamanın yerel içeriği görüntüleyip oynatabilmesi için Fotoğraflar/Dosyalar erişimine ihtiyacı var.';

  @override
  String get allFilesAccessPermission => 'Tüm dosyalara erişim (Önemli)';

  @override
  String get allFilesAccessDescription =>
      'Bu izin, İndirilenler klasöründeki APK\'lar, belgeler ve diğer dosyalar dahil tüm dosyaları göstermek için gereklidir.';

  @override
  String get allFilesAccessDescriptionMacos =>
      'macOS, uygulamanın her klasöre ve sürücüye göz atabilmesi için Tam Disk Erişimi gerektirir. İzin Ver\'e tıklayın, açılan listeye CB File Hub simgesini sürükleyin ve Touch ID veya parolanızla onaylayın, ardından Çık ve Yeniden Aç\'ı seçin.';

  @override
  String get fullDiskAccessHelperTitle => 'CB File Hub\'ı listeye sürükleyin';

  @override
  String get fullDiskAccessHelperMessage =>
      'Bu simgeyi Tam Disk Erişimi listesine sürükleyin, ardından Touch ID veya parolanızla onaylayın. CB File Hub zaten listedeyse yalnızca açın.';

  @override
  String get installPackagesPermission => 'Paket yükleme (APK)';

  @override
  String get installPackagesDescription =>
      'Bu izin, APK dosyalarını açıp Paket Yükleyici ile yüklemek için gereklidir.';

  @override
  String get localNetworkPermission => 'Yerel ağ';

  @override
  String get localNetworkDescription =>
      'Aynı ağdaki SMB/NAS cihazlarına göz atmak için yerel ağa erişime izin verir.';

  @override
  String get notificationsPermission => 'Bildirimler (İsteğe bağlı)';

  @override
  String get notificationsDescription =>
      'Oynatma güncellemelerini ve arka plan görevlerini almak için bildirimleri etkinleştirin.';

  @override
  String get grantAllPermissions => 'Tüm izinleri ver';

  @override
  String get grantingPermissions => 'İzinler veriliyor...';

  @override
  String get enterApp => 'Uygulamaya gir';

  @override
  String get skipEnterApp => 'Atla, uygulamaya gir';

  @override
  String get granted => 'Verildi';

  @override
  String get grantPermission => 'İzin ver';

  // Home screen
  @override
  String get welcomeToFileManager => 'CB File Hub\'a hoş geldiniz';

  @override
  String get welcomeDescription => 'Güçlü dosya yönetimi yardımcınız';

  @override
  String get quickActions => 'Hızlı eylemler';

  @override
  String get browseFiles => 'Dosyalara göz at';

  @override
  String get browseFilesDescription => 'Yerel dosya ve klasörlerinizi keşfedin';

  @override
  String get manageMedia => 'Medyayı yönet';

  @override
  String get manageMediaDescription =>
      'Görselleri ve videoları galeride görüntüleyin';

  @override
  String get tagFiles => 'Dosyaları etiketle';

  @override
  String get tagFilesDescription => 'Dosyaları akıllı etiketlerle düzenleyin';

  @override
  String get networkAccess => 'Ağ erişimi';

  @override
  String get networkAccessDescription =>
      'Ağ sürücülerine ve paylaşımlarına göz atın';

  @override
  String get keyFeatures => 'Temel özellikler';

  @override
  String get fileManagement => 'Dosya yönetimi';

  @override
  String get fileManagementDescription =>
      'Dosyalarınıza kolayca göz atın ve düzenleyin';

  @override
  String get smartTagging => 'Akıllı etiketleme';

  @override
  String get smartTaggingDescription =>
      'Şimşek hızında arama için dosyaları etiketleyin';

  @override
  String get mediaGallery => 'Medya galerisi';

  @override
  String get mediaGalleryDescription =>
      'Görseller ve videolar için güzel bir galeri';

  @override
  String get networkSupport => 'Ağ desteği';

  @override
  String get networkSupportDescription => 'Ağ sürücülerine kesintisiz erişim';

  // Settings screen
  @override
  String get interface => 'Arayüz';

  @override
  String get selectInterfaceTheme => 'Arayüzü ve sevdiğiniz renkleri seçin';

  @override
  String get chooseInterface => 'Arayüz seç';

  @override
  String get interfaceDescription => 'Çeşitli renkler ve stiller';

  @override
  String get showFileTags => 'Dosya etiketlerini göster';

  @override
  String get showFileTagsDescription =>
      'Dosya etiketlerini tüm görünüm modlarında dosya listesinin dışında göster';

  @override
  String get showFileTagsToggle => 'Dosya etiketlerini göster';

  @override
  String get showFileTagsToggleDescription =>
      'Etiketlerin dosya listesinin dışında gösterilmesini aç/kapat';

  @override
  String get fileThumbnailFit => 'Dosya küçük resmi görünümü';

  @override
  String get fileThumbnailFitDescription =>
      'Dosya küçük resimlerinin çerçeveyi doldurmasını mı yoksa görselin tamamını mı göstermesini istediğinizi seçin';

  @override
  String get tagThumbnailFit => 'Etiket küçük resmi görünümü';

  @override
  String get tagThumbnailFitDescription =>
      'Etiket küçük resimlerinin görselin tamamını mı yoksa çerçeveyi dolduracak şekilde mi gösterileceğini seçin';

  @override
  String get thumbnailFitContain => 'Görselin tamamını göster';

  @override
  String get thumbnailFitCover => 'Çerçeveyi doldur';

  @override
  String get rememberTabWorkspace => 'Sekme çalışma alanını hatırla';

  @override
  String get rememberTabWorkspaceDescription =>
      'Son açılan sekmeyi geri yükle ve çekmece daraltma durumunu sekme başına koru.';

  @override
  String get tabInactiveThreshold => 'Sekme etkin olmama süresi';

  @override
  String get tabInactiveThresholdDescription =>
      'Bir sekme bu süre boyunca dokunulmadan kaldığında otomatik olarak askıya alınır ve önbellekleri serbest bırakılır. Sekmeleri her zaman etkin tutmak için "Kapalı" seçin.';

  @override
  String get tabInactiveThresholdDisabled => 'Kapalı';

  @override
  String get tabInactiveThresholdMinutesValue => 'dakika';

  @override
  String get tabInactiveThresholdHoursValue => 'saat';

  @override
  String get cacheManagement => 'Önbellek yönetimi';

  @override
  String get cacheManagementDescription =>
      'Belleği boşaltmak için önbellek verilerini temizleyin';

  @override
  String get appDataManagement => 'Uygulama verisi yönetimi';

  @override
  String get appDataManagementDescription =>
      'Önbelleğe alınan ve saklanan uygulama verilerini gözden geçirin ve temizleyin';

  @override
  String get documentsData => 'Saklanan veriler';

  @override
  String get documentsDataDescription =>
      'Belgeler klasöründe tutulan ve önbellek temizliğinden etkilenmeyen kalıcı dosyalar';

  @override
  String get tagThumbnails => 'Etiket küçük resimleri';

  @override
  String get tagThumbnailsDescription =>
      'Etiket küçük resmi olarak seçtiğiniz görseller (çıkarılan video kareleri)';

  @override
  String get clearTagThumbnails => 'Etiket küçük resimlerini temizle';

  @override
  String get tagThumbnailsCleared => 'Etiket küçük resimleri temizlendi';

  @override
  String get documentsRoot => 'Belgeler kök dizini';

  @override
  String get cacheFolder => 'Önbellek klasörü:';

  @override
  String get networkThumbnails => 'Ağ küçük resimleri:';

  @override
  String get videoThumbnailsCache => 'Video küçük resimleri:';

  @override
  String get tempFiles => 'Geçici dosyalar:';

  @override
  String get videoLibraryCache => 'Video galerisi önbelleği:';

  @override
  String get clearVideoLibraryCache => 'Video galerisi önbelleğini temizle';

  @override
  String get videoLibraryCacheCleared => 'Video galerisi önbelleği temizlendi';

  @override
  String get notInitialized => 'Başlatılmadı';

  @override
  String get refreshCacheInfo => 'Yenile';

  @override
  String get cacheInfoUpdated => 'Önbellek bilgisi güncellendi';

  @override
  String get clearVideoThumbnailsCache =>
      'Video küçük resim önbelleğini temizle';

  @override
  String get clearVideoThumbnailsDescription =>
      'Oluşturulan video küçük resimlerini temizle';

  @override
  String get clearNetworkThumbnailsCache =>
      'SMB/ağ küçük resim önbelleğini temizle';

  @override
  String get clearNetworkThumbnailsDescription =>
      'Oluşturulan ağ küçük resimlerini temizle';

  @override
  String get clearTempFilesCache => 'Geçici dosyaları temizle';

  @override
  String get clearTempFilesDescription =>
      'Ağ paylaşımlarındaki geçici dosyaları temizle';

  @override
  String get clearAllCache => 'Tüm önbelleği temizle';

  @override
  String get clearAllCacheDescription => 'Tüm önbellek verilerini temizle';

  @override
  String get videoCacheCleared => 'Video küçük resim önbelleği temizlendi';

  @override
  String get networkCacheCleared => 'Ağ küçük resim önbelleği temizlendi';

  @override
  String get tempFilesCleared => 'Geçici dosyalar temizlendi';

  @override
  String get allCacheCleared => 'Tüm önbellek verileri temizlendi';

  @override
  String get errorClearingCache => 'Hata: ';

  // Clipboard actions
  @override
  String copiedToClipboard(String name) => '"$name" panoya kopyalandı';
  @override
  String cutToClipboard(String name) => '"$name" panoya kesildi';
  @override
  String get pasting => 'Yapıştırılıyor...';

  // Rename dialogs
  @override
  String get renameFileTitle => 'Dosyayı yeniden adlandır';
  @override
  String get renameFolderTitle => 'Klasörü yeniden adlandır';
  @override
  String currentNameLabel(String name) => 'Geçerli ad: $name';
  @override
  String get newNameLabel => 'Yeni ad';

  @override
  String get renameShortcutHint => 'Kaydetmek için Enter · İptal için Esc';

  @override
  String get renameNameRequired => 'Ad boş olamaz';

  @override
  String get renameInvalidCharacters => 'Bir ad \\ / : * ? " < > | içeremez';
  @override
  String renamedFileTo(String newName) =>
      'Dosya "$newName" olarak yeniden adlandırıldı';
  @override
  String renamedFolderTo(String newName) =>
      'Klasör "$newName" olarak yeniden adlandırıldı';
  @override
  String get allowFileExtensionRename =>
      'Dosya uzantılarının düzenlenmesine izin ver';

  // Downloads
  @override
  String downloadedTo(String location) => '$location konumuna indirildi';
  @override
  String downloadFailed(String error) => 'İndirme başarısız: $error';

  // Folder / Trash
  @override
  String get items => 'öğe';

  @override
  String get files => 'dosya';

  @override
  String get deleteTitle => 'Sil';

  @override
  String get permanentDeleteTitle => 'Kalıcı olarak sil';

  @override
  String confirmDeletePermanent(String name) =>
      '"$name" öğesini kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';

  @override
  String confirmDeletePermanentMultiple(int count) =>
      '$count öğeyi kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';

  @override
  String movedToTrash(String name) => '$name çöp kutusuna taşındı';
  @override
  String moveItemsToTrashConfirmation(int count, String itemType) =>
      '$count $itemType çöp kutusuna taşınsın mı?';
  @override
  String get moveItemsToTrashDescription =>
      'Bu öğeler çöp kutusuna taşınacak. Gerekirse daha sonra geri yükleyebilirsiniz.';
  @override
  String get clearFilter => 'Filtreyi temizle';
  @override
  String filteredBy(String filter) => 'Filtre: $filter';
  @override
  String noFilesMatchFilter(String filter) =>
      '"$filter" filtresiyle eşleşen dosya yok';

  // Trash / Recycle Bin screen
  @override
  String get emptyTrash => 'Çöp kutusunu boşalt';
  @override
  String get emptyingTrash => 'Çöp kutusu boşaltılıyor…';
  @override
  String get emptyTrashConfirm =>
      'Çöp kutusundaki tüm öğeleri kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  @override
  String get emptyTrashButton => 'ÇÖP KUTUSUNU BOŞALT';
  @override
  String permanentlyDeleteItemsTitle(int count) =>
      '$count öğe kalıcı olarak silinsin mi?';
  @override
  String get confirmPermanentlyDeleteThese =>
      'Bu işlem geri alınamaz. Bu öğeleri kalıcı olarak silmek istediğinizden emin misiniz?';
  @override
  String itemRestoredSuccess(String name) => '$name başarıyla geri yüklendi';
  @override
  String failedToRestore(String name) => '$name geri yüklenemedi';
  @override
  String errorRestoringItemWithError(String error) =>
      'Öğe geri yüklenirken hata: $error';
  @override
  String itemPermanentlyDeleted(String name) => '$name kalıcı olarak silindi';
  @override
  String failedToDelete(String name) => '$name silinemedi';
  @override
  String failedToDeleteFilesCount(int count) => '$count dosya silinemedi';
  @override
  String failedToDeleteItemsCount(int count) => '$count öğe silinemedi';
  @override
  String errorDeletingItemWithError(String error) =>
      'Öğe silinirken hata: $error';
  @override
  String get trashEmptiedSuccess => 'Çöp kutusu başarıyla boşaltıldı';
  @override
  String get failedToEmptyTrash => 'Çöp kutusu boşaltılamadı';
  @override
  String errorEmptyingTrashWithError(String error) =>
      'Çöp kutusu boşaltılırken hata: $error';
  @override
  String itemsRestoredSuccess(int count) =>
      '$count öğe başarıyla geri yüklendi';
  @override
  String itemsRestoredWithFailures(int success, int failed) =>
      '$success öğe başarıyla geri yüklendi, $failed öğe başarısız';
  @override
  String itemsPermanentlyDeletedCount(int count) =>
      '$count öğe kalıcı olarak silindi';
  @override
  String itemsDeletedWithFailures(int success, int failed) =>
      '$success öğe kalıcı olarak silindi, $failed öğe başarısız';
  @override
  String errorRestoringItemsWithError(String error) =>
      'Öğeler geri yüklenirken hata: $error';
  @override
  String errorDeletingItemsWithError(String error) =>
      'Öğeler silinirken hata: $error';
  @override
  String errorDeletingFilesWithError(String error) =>
      'Dosyalar silinirken hata: $error';
  @override
  String errorOpeningRecycleBinWithError(String error) =>
      'Geri Dönüşüm Kutusu açılırken hata: $error';
  @override
  String get restoreSelected => 'Seçilenleri geri yükle';
  @override
  String get deleteSelected => 'Seçilenleri sil';
  @override
  String get selectItems => 'Öğeleri seç';
  @override
  String get openRecycleBin => 'Geri Dönüşüm Kutusu\'nu aç';
  @override
  String get emptyTrashTooltip => 'Çöp kutusunu boşalt';
  @override
  String get trashIsEmpty => 'Çöp kutusu boş';
  @override
  String get itemsDeletedWillAppearHere => 'Sildiğiniz öğeler burada görünür';
  @override
  String originalLocation(String path) => 'Özgün konum: $path';
  @override
  String deletedAt(String date, String size) => 'Silindi: $date • $size';
  @override
  String get systemLabel => 'Sistem';
  @override
  String errorLoadingTrashItemsWithError(String error) =>
      'Çöp kutusu öğeleri yüklenirken hata: $error';
  @override
  String get restoreTooltip => 'Geri yükle';
  @override
  String get deletePermanentlyTooltip => 'Kalıcı olarak sil';
  @override
  String get columnDateDeleted => 'Silinme tarihi';
  @override
  String get columnOriginalPath => 'Özgün yol';
  @override
  String get askCbAgentAboutThisFile => 'CB Agent\'a bu dosyayı sor';
  @override
  String get askCbAgentAboutThisFolder => 'CB Agent\'a bu klasörü sor';

  // Misc helper labels
  @override
  String get networkFile => 'Ağ dosyası';
  @override
  String tagCount(int count) => '$count etiket';

  // Generic errors
  @override
  String errorGettingFolderProperties(String error) =>
      'Klasör özellikleri alınırken hata: $error';
  @override
  String errorSavingTags(String error) =>
      'Etiketler kaydedilirken hata: $error';
  @override
  String errorCreatingFolder(String error) =>
      'Klasör oluşturulurken hata: $error';
  @override
  String get pathNotAccessible => 'Yol mevcut değil veya erişilemiyor';

  // UI labels
  @override
  String get noStorageLocationsFound => 'Depolama konumu bulunamadı';
  @override
  String get driveGroupFixed => 'Bu bilgisayar';
  @override
  String get driveGroupRemovable => 'Çıkarılabilir';
  @override
  String get driveGroupNetwork => 'Ağ';
  @override
  String get driveGroupOther => 'Diğer';
  @override
  String get driveTapToBrowse => 'Göz atmak için dokunun';
  @override
  String get driveRestrictedAccess => 'Kısıtlı erişim';
  @override
  String get driveEject => 'Çıkar';
  @override
  String get driveEjectConfirmTitle => 'Sürücü çıkarılsın mı?';
  @override
  String driveEjectConfirmMessage(String name) =>
      '"$name" güvenle kaldırılsın mı? Hiçbir dosyanın kullanımda olmadığından emin olun.';
  @override
  String get driveEjectSuccess => 'Sürücü çıkarıldı';
  @override
  String driveEjectFailed(String error) => 'Çıkarılamadı: $error';
  @override
  String get driveRename => 'Yeniden adlandır';
  @override
  String get driveRenameTitle => 'Birimi yeniden adlandır';
  @override
  String get driveRenameHint => 'Birim etiketi';
  @override
  String get driveRenameSuccess => 'Birim yeniden adlandırıldı';
  @override
  String driveRenameFailed(String error) => 'Yeniden adlandırılamadı: $error';
  @override
  String get driveFormatConfirmTitle => 'Sürücü biçimlendirilsin mi?';
  @override
  String driveFormatConfirmMessage(String name) =>
      '"$name" için sistem biçimlendirme aracı açılsın mı? Bu işlem birimdeki tüm verileri silebilir.';
  @override
  String get driveOpenInCleaner => 'Disk Temizleyici\'de aç';
  @override
  String get driveUsed => 'Kullanılan';
  @override
  String get driveFree => 'Boş';
  @override
  String get driveTotal => 'Toplam';
  @override
  String get driveType => 'Tür';
  @override
  String get driveFilesystem => 'Dosya sistemi';
  @override
  String get driveSerial => 'Seri no';
  @override
  String get driveKindFixed => 'Yerel disk';
  @override
  String get driveKindRemovable => 'Çıkarılabilir';
  @override
  String get driveKindNetwork => 'Ağ';
  @override
  String get driveKindOptical => 'Optik';
  @override
  String get driveKindRam => 'RAM diski';
  @override
  String get driveKindInternal => 'Dahili depolama';
  @override
  String get driveKindUnknown => 'Depolama';
  @override
  String get openInNewPane => 'Yeni bölmede aç';
  @override
  String get openInWindowsTerminal => 'Windows Terminal\'de aç';
  @override
  String get driveCleanup => 'Temizle';
  @override
  String get driveFormat => 'Biçimlendir';
  @override
  String get driveBitLocker => 'BitLocker\'ı aç';
  @override
  String get menuPinningOnlyLargeScreens =>
      'Menü sabitleme yalnızca daha büyük ekranlarda kullanılabilir';

  @override
  String get pinMenu => 'Menüyü sabitle';

  @override
  String get unpinMenu => 'Menü sabitlemesini kaldır';

  @override
  String get pinnedSection => 'Sabitlenenler';
  @override
  String get favoritesSection => 'Favoriler';
  @override
  String get sidebarApplications => 'Uygulamalar';
  @override
  String get sidebarDesktop => 'Masaüstü';
  @override
  String get sidebarPictures => 'Resimler';
  @override
  String get sidebarMusic => 'Müzik';
  @override
  String get sidebarMovies => 'Filmler';

  @override
  String get pinToSidebar => 'Kenar çubuğuna sabitle';

  @override
  String get unpinFromSidebar => 'Kenar çubuğundan kaldır';

  @override
  String get pinnedToSidebar => 'Kenar çubuğuna sabitlendi';

  @override
  String get removedFromSidebar => 'Kenar çubuğundan kaldırıldı';

  @override
  String get exitApplicationTitle => 'Uygulamadan çıkılsın mı?';
  @override
  String moveToTrashConfirmMessage(String name) =>
      '"$name" öğesini çöp kutusuna taşımak istediğinizden emin misiniz?';
  @override
  String get exitApplicationConfirm =>
      'Uygulamadan çıkmak istediğinizden emin misiniz?';
  @override
  String itemsSelected(int count) => '$count seçildi';
  @override
  String itemsCount(int count) => '$count öğe';
  @override
  String get noActiveTab => 'Etkin sekme yok';
  @override
  String get masonryLayoutName => 'Mozaik düzen (Pinterest)';
  @override
  String get undo => 'Geri al';
  @override
  String errorWithMessage(String message) => 'Hata: $message';
  @override
  String get referencedFile => 'Başvurulan dosya';
  @override
  String referencedFiles(int count) => '$count başvurulan dosya';
  @override
  String pathsCopied(int count) => '$count yol kopyalandı';
  @override
  String get moveToTrashTitle => 'Çöp kutusuna taşı';
  @override
  String get imageMovedToTrash => 'Görsel çöp kutusuna taşındı';
  @override
  String get failedToMoveImageToTrash => 'Görsel çöp kutusuna taşınamadı';
  @override
  String failedToMoveImageToTrashWithError(String error) =>
      'Görsel çöp kutusuna taşınamadı: $error';
  @override
  String get copiedPathToClipboard => 'Yol panoya kopyalandı';
  @override
  String get unableToOpenWithExternalApp => 'Harici uygulamayla açılamıyor';
  @override
  String failedToDisplayImageInformation(String error) =>
      'Görsel bilgisi görüntülenemedi: $error';
  @override
  String removedFromAlbum(int count) => 'Albümden $count görsel kaldırıldı';
  @override
  String get addingFilesInBackground => 'Dosyalar arka planda ekleniyor...';
  @override
  String addedFilesProgress(int added, int total) =>
      '$total dosyadan $added tanesi eklendi';
  @override
  String get filesAddedSuccessfully => 'Dosyalar başarıyla eklendi';

  @override
  String get processing => 'İşleniyor...';

  @override
  String get deletingFiles => 'Dosyalar siliniyor...';

  @override
  String get deletingItems => 'Öğeler siliniyor...';

  @override
  String get movingItemsToTrash => 'Öğeler çöp kutusuna taşınıyor...';

  @override
  String get done => 'Bitti';

  @override
  String get regenerateThumbnailsWithNewPosition =>
      'Küçük resimleri yeni konumla yeniden oluştur';

  @override
  String get thumbnailPositionUpdated =>
      'Önbellek temizlendi, küçük resimler şu konumda yeniden oluşturulacak: ';

  @override
  String get fileTagsEnabled => 'Dosya etiketi gösterimi etkin';

  @override
  String get fileTagsDisabled => 'Dosya etiketi gösterimi devre dışı';

  // System screen router
  @override
  String get unknownSystemPath => 'Bilinmeyen sistem yolu';

  @override
  String get ftpConnectionRequired => 'FTP bağlantısı gerekli';

  @override
  String get ftpConnectionDescription =>
      'Önce bir FTP sunucusuna bağlanmanız gerekir.';

  @override
  String get goToFtpConnections => 'FTP bağlantılarına git';

  @override
  String get cannotOpenNetworkPath => 'Ağ yolu açılamıyor';

  @override
  String get goBack => 'Geri dön';

  @override
  String get tagPrefix => 'Etiket';

  // Network browsing
  @override
  String get ftpConnections => 'FTP bağlantıları';

  @override
  String get smbNetwork => 'SMB ağı';

  @override
  String get refreshData => 'Yenile';

  @override
  String get addConnection => 'Bağlantı ekle';

  @override
  String get noFtpConnections => 'FTP bağlantısı yok.';

  @override
  String get activeConnections => 'Etkin bağlantılar';

  @override
  String get savedConnections => 'Kayıtlı bağlantılar';
  @override
  String get connecting => 'Bağlanılıyor';

  @override
  String get connect => 'Bağlan';

  @override
  String get unknown => 'Bilinmiyor';

  @override
  String get connectionError => 'Bağlantı hatası';

  @override
  String get loadCredentialsError =>
      'Kayıtlı kimlik bilgileri yüklenirken hata';

  @override
  String get networkScanFailed => 'Ağ taraması başarısız';

  @override
  String get smbVersionUnknown => 'Bilinmiyor';

  @override
  String get connectionInfoUnavailable => 'Bağlantı bilgisi kullanılamıyor';

  @override
  String get networkSettingsOpened => 'Ağ ayarları açıldı';

  @override
  String get cannotOpenNetworkSettings =>
      'Ağ ayarları açılamıyor, lütfen elle açın';

  @override
  String get networkDiscoveryDisabled => 'Ağ bulma etkin olmayabilir';

  @override
  String get networkDiscoveryDescription =>
      'SMB sunucularını taramak için Windows ayarlarında ağ bulmayı etkinleştirin';

  @override
  String get openSettings => 'Ayarları aç';

  @override
  String get activeConnectionsTitle => 'Etkin bağlantılar';

  @override
  String get activeConnectionsDescription => 'Bağlı olduğunuz SMB sunucuları';

  @override
  String get discoveredSmbServers => 'Bulunan SMB sunucuları';

  @override
  String get discoveredSmbServersDescription =>
      'Yerel ağınızda bulunan sunucular';

  @override
  String get noActiveSmbConnections => 'Etkin SMB bağlantısı yok';

  @override
  String get connectToSmbServer =>
      'Burada görmek için bir SMB sunucusuna bağlanın';

  @override
  String get connected => 'Bağlı';

  @override
  String get openConnection => 'Bağlantıyı aç';

  @override
  String get disconnect => 'Bağlantıyı kes';

  @override
  String get scanningForSmbServers => 'SMB sunucuları taranıyor...';

  @override
  String get devicesWillAppear => 'Cihazlar bulundukça burada görünecek';

  @override
  String get scanningMayTakeTime => 'Bu işlem birkaç dakika sürebilir';

  @override
  String get noSmbServersFound => 'SMB sunucusu bulunamadı';

  @override
  String get tryScanningAgain =>
      'Yeniden taramayı deneyin veya ağ ayarlarınızı kontrol edin';

  @override
  String get scanAgain => 'Yeniden tara';

  @override
  String get readyToScan => 'Taramaya hazır';

  @override
  String get clickRefreshToScan =>
      'SMB sunucularını taramaya başlamak için yenile düğmesine tıklayın';

  @override
  String get startScan => 'Taramayı başlat';

  @override
  String get foundDevices => 'Bulunan';

  @override
  String get scanning => 'Taranıyor...';

  @override
  String get scanComplete => 'Tarama tamamlandı';

  @override
  String get smbVersion => 'SMB sürümü';

  @override
  String get netbios => 'NetBIOS';

  // Network - additional
  @override
  String get selectAll => 'Tümünü seç';
  @override
  String get unknownError => 'Bilinmeyen bir hata oluştu.';
  @override
  String get networkConnections => 'Ağ bağlantıları';
  @override
  String get availableServices => 'Kullanılabilir hizmetler';
  @override
  String get noActiveNetworkConnections => 'Etkin ağ bağlantısı yok';
  @override
  String get useAddButtonToAddConnection =>
      'Yeni bir bağlantı eklemek için (+) düğmesini kullanın';
  @override
  String get unknownConnection => 'Bilinmeyen bağlantı';
  @override
  String serviceTypeConnection(String serviceName) => '$serviceName bağlantısı';
  @override
  String get noServicesAvailable => 'Kullanılabilir hizmet yok';
  @override
  String get webdavConnections => 'WebDAV bağlantıları';
  @override
  String errorOpeningTab(String tabName, String error) =>
      '$tabName için sekme açılırken hata: $error';
  @override
  String connectToServiceServer(String serviceName) =>
      '$serviceName sunucusuna bağlan';
  @override
  String get serviceType => 'Hizmet türü';
  @override
  String get host => 'Ana bilgisayar';
  @override
  String get deleteSavedConnection => 'Kayıtlı bağlantıyı sil';
  @override
  String get username => 'Kullanıcı adı';
  @override
  String get password => 'Parola';
  @override
  String get portOptional => 'Port (isteğe bağlı)';
  @override
  String get useSslTls => 'SSL/TLS kullan';
  @override
  String get basePathOptional => 'Temel yol (isteğe bağlı)';
  @override
  String get basePathHint => 'ör. /webdav';
  @override
  String get domainOptional => 'Etki alanı (isteğe bağlı)';
  @override
  String get saveCredentials => 'Kimlik bilgilerini kaydet';
  @override
  String get saveCredentialsDescription =>
      'Gelecekteki bağlantılar için oturum açma bilgilerini sakla';
  @override
  String get deleteSavedConnectionTitle => 'Kayıtlı bağlantı silinsin mi?';
  @override
  String deleteSavedConnectionConfirm(String host) =>
      '"$host" için kayıtlı bağlantıyı silmek istediğinizden emin misiniz?';
  @override
  String connectionDeleted(String host) => '"$host" bağlantısı silindi.';
  @override
  String connectionNotFoundToDelete(String host) =>
      'Silinecek "$host" bağlantısı bulunamadı.';
  @override
  String get errorDeletingConnection => 'Bağlantı silinirken hata';
  @override
  String connectionFailed(String error) => 'Bağlantı başarısız: $error';
  @override
  String get networkConnection => 'Ağ bağlantısı';
  @override
  String get notConnected => 'Bağlı değil';
  @override
  String get refreshSmbVersionInfo => 'SMB sürüm bilgisini yenile';
  @override
  String shareLabel(String sharePath) => 'Paylaşım: $sharePath';
  @override
  String get rootShare => 'Kök paylaşım';
  @override
  String foundDevicesCount(int count) => '$count cihaz bulundu';
  @override
  String get noWebdavConnections => 'WebDAV bağlantısı yok.';
  @override
  String get addConnectionOrSampleToStart =>
      'Başlamak için yeni bir bağlantı veya örnek ekleyin.';
  @override
  String get addSample => 'Örnek ekle';
  @override
  String get editWebdavConnection => 'WebDAV bağlantısını düzenle';
  @override
  String get update => 'Güncelle';
  @override
  String get connectionUpdatedSuccess => 'Bağlantı başarıyla güncellendi';
  @override
  String get failedToUpdateConnection => 'Bağlantı güncellenemedi';
  @override
  String get deleteConnection => 'Bağlantıyı sil';
  @override
  String deleteConnectionConfirm(String host) =>
      '"$host" bağlantısını silmek istediğinizden emin misiniz?';
  @override
  String get connectionDeletedSuccess => 'Bağlantı başarıyla silindi';
  @override
  String get failedToDeleteConnection => 'Bağlantı silinemedi';
  @override
  String get addSampleWebdavConnection => 'Örnek WebDAV bağlantısı ekle';
  @override
  String get sampleConnectionAddedSuccess => 'Örnek bağlantı başarıyla eklendi';
  @override
  String get failedToAddSampleConnection => 'Örnek bağlantı eklenemedi';
  @override
  String lastConnected(String dateStr) => 'Son bağlantı: $dateStr';
  @override
  String get editConnection => 'Bağlantıyı düzenle';
  @override
  String get closeConnection => 'Bağlantıyı kapat';
  @override
  String get retry => 'Yeniden dene';
  @override
  String get networkErrorPersistsHint =>
      'Bu hata devam ederse ağ bağlantınızı ve sunucu durumunu kontrol edin.';
  @override
  String get pleaseEnterHost => 'Lütfen bir ana bilgisayar girin';
  @override
  String get pleaseEnterPort => 'Lütfen bir port girin';
  @override
  String get pleaseEnterValidPort => 'Lütfen geçerli bir port numarası girin';
  @override
  String get connectionMode => 'Bağlantı modu:';
  @override
  String get passive => 'Pasif';
  @override
  String get active => 'Etkin';
  @override
  String get port => 'Port';
  @override
  String get basePath => 'Temel yol';

  // Drawer menu items
  @override
  String get networksMenu => 'Ağlar';

  @override
  String get networkTab => 'Ağ';

  @override
  String get about => 'Hakkında';

  // Tab manager
  @override
  String get newTabButton => 'Yeni sekme';

  @override
  String get openNewTabToStart => 'Başlamak için yeni bir sekme açın';

  @override
  String get tabManager => 'Sekme yöneticisi';

  @override
  String get openTabs => 'Açık sekmeler';

  @override
  String get noTabsOpen => 'Açık sekme yok';

  @override
  String get closeAllTabs => 'Tüm sekmeleri kapat';

  @override
  String get activeTab => 'Etkin';

  @override
  String get closeTab => 'Sekmeyi kapat';

  @override
  String get closeOtherTabs => 'Diğer sekmeleri kapat';

  @override
  String get markTabInactive => 'Etkin değil olarak işaretle';

  @override
  String get restoringTab => 'Sekme geri yükleniyor…';

  @override
  String get keepTabAlwaysActive => 'Sekmeyi her zaman etkin tut';

  @override
  String get allowTabAutoSuspend =>
      'Sekmenin otomatik askıya alınmasına izin ver';

  @override
  String get tabAlwaysActiveTooltip => 'Her zaman etkin';

  @override
  String get addNewTab => 'Yeni sekme ekle';

  // Desktop windows (tabbed browsing)
  @override
  String get newWindow => 'Yeni pencere';

  @override
  String get moveTabToNewWindow => 'Sekmeyi yeni pencereye taşı';

  @override
  String get moveTabToWindow => 'Sekmeyi pencereye taşı...';

  @override
  String get mergeWindowIntoThis => 'Pencereyi buna birleştir...';

  @override
  String get selectWindow => 'Pencere seç';

  @override
  String get noOtherWindows => 'Başka pencere yok';

  // Home screen
  @override
  String get welcomeTitle => 'CB File Hub\'a hoş geldiniz';

  @override
  String get welcomeSubtitle => 'Güçlü dosya yönetimi yardımcınız';

  @override
  String get quickActionsTip =>
      'İpucu: Hızlıca başlamak için aşağıdaki hızlı eylemleri kullanın';

  @override
  String get quickActionsHome => 'Hızlı eylemler';

  @override
  String get startHere => 'Buradan başlayın';

  @override
  String get newTabAction => 'Yeni sekme';

  @override
  String get newTabActionDesc => 'Yeni bir dosya tarayıcısı sekmesi aç';

  @override
  String get tagsAction => 'Etiketler';

  @override
  String get tagsActionDesc => 'Akıllı etiketlerle düzenleyin';

  @override
  String get imageGalleryTab => 'Görsel galerisi';

  @override
  String get videoGalleryTab => 'Video galerisi';

  @override
  String get drivesTab => 'Sürücüler';

  @override
  String get browseTab => 'Gözat';

  @override
  String get documentsTab => 'Belgeler';

  @override
  String get homeTab => 'Ana Sayfa';

  @override
  String get internalStorage => 'Dahili depolama';

  @override
  String get storagePrefix => 'Depolama';

  @override
  String get rootFolder => 'Kök';

  // Video Hub
  @override
  String get videoHub => 'Video Merkezi';

  @override
  String get manageYourVideos => 'Videolarınızı yönetin';

  @override
  String get videos => 'Videolar';

  @override
  String get videoActions => 'Video eylemleri';

  @override
  String get allVideos => 'Tüm videolar';
  @override
  String get browseAllYourVideos => 'Tüm videolarınıza göz atın';

  @override
  String get videosFolder => 'Videolar klasörü';

  @override
  String get openFileManager => 'Dosya yöneticisini aç';

  @override
  String get videoStatistics => 'Video istatistikleri';

  @override
  String get totalVideos => 'Toplam video';

  // Gallery Hub
  @override
  String get galleryHub => 'Galeri Merkezi';

  @override
  String get managePhotosAndAlbums =>
      'Fotoğraflarınızı ve albümlerinizi yönetin';

  @override
  String get images => 'Görseller';

  @override
  String get galleryActions => 'Galeri eylemleri';

  @override
  String get quickAccess => 'Hızlı erişim';

  @override
  String get thisPC => 'Bu bilgisayar';

  @override
  String get browseAllYourPictures => 'Tüm resimlerinize göz atın';

  @override
  String get browseAllYourPhotos => 'Tüm fotoğraflarınıza göz atın';

  @override
  String get organizeInAlbums => 'Albümlerde düzenleyin';

  @override
  String get picturesFolder => 'Resimler klasörü';

  @override
  String get photosFromCamera => 'Kameradan fotoğraflar';

  @override
  String get downloadedFiles => 'İndirilen dosyalar';

  @override
  String get downloadedImages => 'İndirilen görseller';

  @override
  String get featuredAlbums => 'Öne çıkan albümler';

  @override
  String get personalized => 'Kişiselleştirilmiş';

  @override
  String get configureFeaturedAlbums => 'Öne çıkan albümleri yapılandır';

  @override
  String get noFeaturedAlbums => 'Öne çıkan albüm yok';

  @override
  String get createSomeAlbumsToSeeThemFeaturedHere =>
      'Burada öne çıkarılmış görmek için bazı albümler oluşturun';

  @override
  String get removeFromFeatured => 'Öne çıkanlardan kaldır';

  @override
  String get galleryStatistics => 'Galeri istatistikleri';

  @override
  String get totalImages => 'Toplam görsel';

  @override
  String get albums => 'Albümler';

  @override
  String get allImages => 'Tüm görseller';

  @override
  String get camera => 'Kamera';

  @override
  String get downloads => 'İndirilenler';

  @override
  String get recent => 'Son kullanılanlar';

  @override
  String get folders => 'Klasörler';

  // Video player playlist
  @override
  String get videoPlaylist => 'Oynatma listesi';

  // Video player screenshot
  @override
  String get takeScreenshot => 'Ekran görüntüsü al';

  @override
  String get screenshotSaved => 'Ekran görüntüsü kaydedildi';

  @override
  String get screenshotSavedAt => 'Ekran görüntüsü şuraya kaydedildi:';

  @override
  String get screenshotFailed => 'Ekran görüntüsü kaydedilemedi';

  @override
  String get screenshotSavedToFolder =>
      'Ekran görüntüsü Ekran Görüntüleri klasörüne kaydedildi';

  @override
  String get openScreenshotFolder => 'Klasörü aç';

  @override
  String get viewScreenshot => 'Görüntüle';

  @override
  String get screenshotNotAvailable => 'Ekran görüntüsü kullanılamıyor';

  @override
  String get screenshotNotAvailableMessage =>
      'Bu kare yakalanamadı. Lütfen videonun yüklenmesini bekleyip yeniden deneyin.';

  @override
  String get screenshotFileNotFound => 'Görsel dosyası bulunamadı';

  @override
  String get screenshotCannotOpenTab => 'Klasör sekmesi bu bağlamda açılamıyor';

  @override
  String get screenshotErrorOpeningFolder => 'Klasör açılırken hata';

  @override
  String get closeAction => 'Kapat';

  @override
  String get pipOverlayEnabled => 'PiP katmanı etkinleştirildi';

  @override
  String get pipAndroidEnableFailed => 'Android\'de PiP etkinleştirilemiyor';

  @override
  String pipError(String error) => 'PiP hatası: $error';

  @override
  String get pipNoSource =>
      'PiP\'yi açmak için kullanılabilir video kaynağı yok';

  @override
  String get pipOpenedInSeparateWindow => 'PiP ayrı bir pencerede açıldı';

  @override
  String get pipNotSupportedOnPlatform => 'PiP bu platformda desteklenmiyor';

  // Video library
  @override
  String get videoLibrary => 'Video kütüphanesi';

  @override
  String get videoLibraries => 'Video kütüphaneleri';

  @override
  String get createVideoLibrary => 'Video kütüphanesi oluştur';

  @override
  String get editVideoLibrary => 'Video kütüphanesini düzenle';

  @override
  String get deleteVideoLibrary => 'Video kütüphanesini sil';

  @override
  String get addVideoSource => 'Video kaynağı ekle';

  @override
  String get removeVideoSource => 'Kaynağı kaldır';

  @override
  String get videoSources => 'Video kaynakları';

  @override
  String get noVideoSources => 'Henüz video kaynağı eklenmedi';

  @override
  String get createImageSource => 'Görsel kaynağı oluştur';

  @override
  String get editImageSource => 'Görsel kaynağını düzenle';

  @override
  String get addImageSource => 'Görsel kaynağı ekle';

  @override
  String get removeImageSource => 'Kaynağı kaldır';

  @override
  String get imageSources => 'Görsel kaynakları';

  @override
  String get noImageSources => 'Henüz görsel kaynağı eklenmedi';

  @override
  String get filterByTags => 'Etiketlere göre filtrele';

  @override
  String get clearTagFilter => 'Filtreyi temizle';

  @override
  String get recentVideos => 'Son videolar';

  @override
  String get videoHubTitle => 'Video Merkezi';

  @override
  String get videoHubWelcome => 'Video kütüphanelerinizi yönetin';

  @override
  String get manageVideoLibraries => 'Video kütüphanelerini yönet';

  @override
  String get videoCount => 'Video sayısı';

  @override
  String get scanForVideos => 'Videoları tara';

  @override
  String get rescanLibrary => 'Kütüphaneyi yeniden tara';

  @override
  String deleteVideoLibraryConfirmation(String name) =>
      '"$name" video kütüphanesi silinsin mi?';

  @override
  String get libraryDeletedSuccessfully => 'Kütüphane başarıyla silindi';

  @override
  String get sourceAdded => 'Kaynak başarıyla eklendi';

  @override
  String get sourceRemoved => 'Kaynak başarıyla kaldırıldı';

  @override
  String get selectVideoSource => 'Video kaynak klasörünü seçin';

  @override
  String get videoLibrarySettings => 'Video kütüphanesi ayarları';

  @override
  String get manageVideoSources => 'Video kaynaklarını yönet';

  @override
  String get videoExtensions => 'Video uzantıları';

  @override
  String get includeSubdirectories => 'Alt dizinleri dahil et';

  @override
  String get noVideosInLibrary => 'Bu kütüphanede video yok';

  @override
  String get libraryCreatedSuccessfully => 'Kütüphane başarıyla oluşturuldu';

  @override
  String videoLibraryCount(int count) => '$count kütüphane';

  @override
  String get libraryCover => 'Kütüphane kapağı';

  @override
  String get changeCoverImage => 'Kapağı değiştir';

  @override
  String get removeCoverImage => 'Kapağı kaldır';

  @override
  String get coverImageUpdated => 'Kapak görseli güncellendi';

  @override
  String get coverImageRemoved => 'Kapak görseli kaldırıldı';

  @override
  String get coverImageUpdateFailed => 'Kapak görseli güncellenemedi';

  @override
  String get lastScanLabel => 'Son tarama';

  @override
  String get neverScanned => 'Hiç taranmadı';

  // Streaming and download dialogs
  @override
  String openFileTypeFile(String fileType) => '$fileType dosyasını aç';
  @override
  String streamDownloadPrompt(String fileType) =>
      '$fileType dosya türü akış için doğrudan desteklenmiyor. Cihazınıza indirmek ister misiniz?';
  @override
  String get downloadingFile => 'Dosya indiriliyor...';
  @override
  String get fileDownloadedSuccess => 'Dosya başarıyla indirildi';
  @override
  String get errorDownloadingFile => 'Dosya indirilirken hata';
  @override
  String get errorTitle => 'Hata';
  @override
  String get mediaPlaybackError => 'Medya oynatma hatası';
  @override
  String mediaPlaybackErrorSmbContent(String error) =>
      'Bu SMB dosyası oynatılamıyor:\n\n$error\n\nLütfen kontrol edin:\n• SMB bağlantısı\n• Dosya yolu\n• Dosya erişim izni';
  @override
  String mediaPlaybackErrorNativeContent(String error) =>
      'Bu SMB dosyası oynatılamıyor:\n\n$error\n\nLütfen kontrol edin:\n• SMB bağlantısı\n• Dosya yolu\n• Dosya erişim izni\n• Yerel SMB istemcisinin kullanılabilirliği';
  @override
  String get chooseAnotherApp => 'Başka bir uygulama seç...';
  @override
  String get folderProperties => 'Klasör özellikleri';
  @override
  String get createNewFolder => 'Yeni klasör oluştur';
  @override
  String get createNewFile => 'Yeni dosya oluştur';
  @override
  String get folderPropertyPath => 'Yol';
  @override
  String get folderPropertyCreated => 'Oluşturulma';
  @override
  String get folderPropertyContent => 'İçerik';
  @override
  String get folderPropertySizeDirectChildren => 'Boyut (doğrudan alt öğeler)';
  @override
  String get networkServiceNotAvailable => 'Ağ hizmeti kullanılamıyor';
  @override
  String get folderNameLabel => 'Klasör adı';
  @override
  String get fileNameLabel => 'Dosya adı';
  @override
  String errorCreatingFile(String error) => 'Dosya oluşturulurken hata: $error';
  @override
  String get noFileSelectedForBenchmarking =>
      'Karşılaştırma testi için dosya seçilmedi';
  @override
  String benchmarkError(String error) => 'Karşılaştırma testi hatası: $error';
  @override
  String benchmarkFailed(String error) =>
      'Karşılaştırma testi başarısız: $error';
  @override
  String get saveTagToLocalDatabaseFailed =>
      'Etiket yerel veritabanına kaydedilemedi';
  @override
  String saveTagFailed(String error) => 'Etiket kaydedilemedi: $error';
  @override
  String debugTagsSeeded(int savedCount, int requestedCount) =>
      '$savedCount/$requestedCount etiket başarıyla eklendi';
  @override
  String debugTagsSeedFailed(String error) =>
      'Etiketler eklenirken hata: $error';
  @override
  String get debugTagsCleared => 'Tüm etiketler temizlendi';
  @override
  String debugTagsClearFailed(String error) =>
      'Etiketler temizlenirken hata: $error';
  @override
  String addFolderToAlbumFailed(String error) =>
      'Klasör eklenirken hata: $error';
  @override
  String addFilesToAlbumFailed(String error) =>
      'Dosyalar eklenirken hata: $error';
  @override
  String loadRulesFailed(String error) => 'Kurallar yüklenirken hata: $error';
  @override
  String openTerminalFailed(String error) => 'Terminal açılamıyor: $error';
  @override
  String startCleanupFailed(String error) => 'Temizlik başlatılamıyor: $error';
  @override
  String startFormatFailed(String error) =>
      'Biçimlendirme başlatılamıyor: $error';
  @override
  String foundResultsWithTag(int count, String tag) =>
      '"$tag" etiketiyle $count sonuç bulundu';

  // AI Agent
  @override
  String get aiSearchAgent => 'Yapay zeka arama aracısı';
  @override
  String get aiSearchAgentDescription =>
      'Akıllı dosya araması için yapay zeka sağlayıcılarını yapılandırın';
  @override
  String get aiProvider => 'Yapay zeka sağlayıcısı';
  @override
  String get aiProviders => 'Yapay zeka sağlayıcıları';
  @override
  String get addProvider => 'Sağlayıcı ekle';
  @override
  String get editProvider => 'Sağlayıcıyı düzenle';
  @override
  String get deleteProvider => 'Sağlayıcıyı sil';
  @override
  String get providerPreset => 'Sağlayıcı ön ayarı';
  @override
  String get selectProviderPreset => 'Bir sağlayıcı ön ayarı seçin';
  @override
  String get providerName => 'Sağlayıcı adı';
  @override
  String get apiType => 'API türü';
  @override
  String get authMode => 'Kimlik doğrulama';
  @override
  String get defaultModel => 'Varsayılan model';
  @override
  String get apiKey => 'API anahtarı';
  @override
  String get codexOauth => 'Codex OAuth';
  @override
  String get endpointUrl => 'Uç nokta URL\'si';
  @override
  String get modelName => 'Model adı';
  @override
  String get openAiCompatible => 'OpenAI uyumlu';
  @override
  String get anthropic => 'Anthropic';
  @override
  String get temperature => 'Sıcaklık';
  @override
  String get maxTokens => 'En fazla belirteç';
  @override
  String get systemPrompt => 'Sistem istemi';
  @override
  String get timeout => 'Zaman aşımı (saniye)';
  @override
  String get maxRetries => 'En fazla yeniden deneme';
  @override
  String get testConnection => 'Bağlantıyı sına';
  @override
  String get connectionSuccess => 'Bağlantı başarılı';
  @override
  String get aiConnectionFailed => 'Bağlantı başarısız';
  @override
  String get enableAiSearch => 'Yapay zeka aramasını etkinleştir';
  @override
  String get defaultSearchScope => 'Varsayılan arama kapsamı';
  @override
  String get maxContentReadSize => 'En fazla içerik okuma boyutu';
  @override
  String get providerEnabled => 'Sağlayıcı etkin';
  @override
  String get providerDisabled => 'Sağlayıcı devre dışı';
  @override
  String get providerPriority => 'Öncelik';
  @override
  String get advancedSettings => 'Gelişmiş ayarlar';
  @override
  String get testingConnection => 'Bağlantı sınanıyor...';
  @override
  String get codexOauthDescription =>
      'Ham API anahtarı yerine yerel Codex/ChatGPT oturumunu kullanın.';
  @override
  String get codexCredentialUnavailable =>
      'Codex kimlik bilgisi yolu bu cihazda kullanılamıyor.';
  @override
  String get codexCredentialMissing =>
      'Codex OAuth kimlik bilgileri bulunamadı. Önce codex login komutunu çalıştırın.';
  @override
  String get launchCodexLogin => 'Codex oturumunu başlat';
  @override
  String get codexLoginLaunched =>
      'Codex oturumu ayrı bir terminal penceresinde başlatıldı.';
  @override
  String get checkCredentials => 'Kimlik bilgilerini denetle';
  @override
  String deleteProviderConfirmation(String name) =>
      '"$name" sağlayıcısını silmek istediğinizden emin misiniz?';
  @override
  String get noProviders => 'Yapılandırılmış yapay zeka sağlayıcısı yok';

  // AI Chat
  @override
  String get aiChat => 'Yapay zeka sohbeti';
  @override
  String get askAiToFindFiles => 'Yapay zekadan dosya bulmasını isteyin...';
  @override
  String get sendMessage => 'Gönder';
  @override
  String get clearChat => 'Sohbeti temizle';
  @override
  String get searchScope => 'Arama kapsamı';
  @override
  String get currentFolder => 'Geçerli klasör';
  @override
  String get recursiveSearch => 'Özyinelemeli arama';
  @override
  String get aiTaggedFiles => 'Etiketli dosyalar';
  @override
  String get allDrives => 'Tüm sürücüler';
  @override
  String get findingFiles => 'Dosyalar bulunuyor...';
  @override
  String get noResultsFound => 'Sonuç bulunamadı';
  @override
  String get aiSearchResults => 'Yapay zeka arama sonuçları';
  @override
  String get retryMessage => 'Yeniden dene';
  @override
  String get providerFallback => 'Sonraki sağlayıcı deneniyor...';
  @override
  String get allProvidersFailed =>
      'Tüm yapay zeka sağlayıcıları başarısız oldu';
  @override
  String get setupAiProvider => 'Ayarlar\'dan bir yapay zeka sağlayıcısı kurun';
  @override
  String get noProviderConfigured =>
      'Yapılandırılmış yapay zeka sağlayıcısı yok';
  @override
  String get aiProviderSettings => 'Yapay zeka sağlayıcı ayarları';
  @override
  String get localModelGuideTitle =>
      'Yapay zekayı kendi cihazınızda çalıştırın';
  @override
  String get localModelGuideIntro =>
      'Bulut sağlayıcıları API anahtarı ister ve her isteği sınırlayabilir veya ücretlendirebilir. Yerel model doğrudan burada çalışır: ücretsiz, sınırsız ve dosyalarınız bu cihazdan çıkmaz.';
  @override
  String get localModelGuideStep1 =>
      'Aşağıdaki düğmeyle Yerel Yapay Zeka ayarlarını açın. Model listesi hemen açılır.';
  @override
  String localModelGuideStep2(String installLabel) =>
      'Bir model seçip "$installLabel" düğmesine tıklayın. Arka planda indirilir, sonra çevrimdışı çalışır.';
  @override
  String get localModelGuideStep3 =>
      'Buraya dönün ve Gönder düğmesinin yanındaki model menüsünden seçin.';
  @override
  String get localModelGuideNote =>
      'Küçük modeller daha az RAM kullanır ve daha hızlı yanıt verir. Hugging Face belirteci yalnızca erişimi kısıtlı modeller için gerekir.';
  @override
  String get localModelGuideOpenSettings => 'Yerel Yapay Zeka ayarlarını aç';
  @override
  String get localModelGuideLater => 'Daha sonra';
  @override
  String get localModelGuideLink => 'Ücretsiz yerel model kullan';
  @override
  String get installLocalModel => 'Model kur';
  @override
  String get localModelRecommended => 'Önerilen';
  @override
  String get localModelInstalledBadge => 'Kuruldu';
  @override
  String get localModelBackgroundHint =>
      'İndirmeler arka planda sürer; bu pencereyi kapatabilirsiniz.';
  @override
  String localModelDownloading(String modelName) => '$modelName indiriliyor';
  @override
  String localModelReady(String modelName) =>
      '$modelName kuruldu ve kullanıma hazır';
  @override
  String get relevanceScore => 'İlgililik';
  @override
  String get aiExplanation => 'Yapay zeka açıklaması';
  @override
  String get aiSearchMode => 'Yapay zeka araması';
  @override
  String get switchToAiSearch => 'Yapay zeka aramasına geç';
  @override
  String get switchToNormalSearch => 'Normal aramaya geç';
  @override
  String get aiChatTab => 'Yapay zeka sohbeti';
  @override
  String get suggestRecentPhotos => 'Son fotoğrafları bul';
  @override
  String get suggestLargeVideos => 'Büyük videoları göster';
  @override
  String get suggestTaggedFiles => 'Şu etiketli dosyalar...';
  @override
  String get fetchModels => 'Modelleri getir';
  @override
  String get fetchingModels => 'Modeller getiriliyor...';
  @override
  String get loadingModels => 'Modeller yükleniyor...';
  @override
  String get noModelsFound => 'Model bulunamadı';
  @override
  String get noModelConfigured => 'Model yok';
  @override
  String get selectModel => 'Bir model seçin';
  @override
  String get modelSearchHint => 'Model ara...';
  @override
  String fetchModelsError(String error) => 'Modeller getirilemedi: $error';
  @override
  String get newConversation => 'Yeni sohbet';
  @override
  String get conversations => 'Sohbetler';
  @override
  String get deleteConversation => 'Sohbeti sil';
  @override
  String get noConversations => 'Henüz sohbet yok';

  // CB Agent rebrand
  @override
  String get cbAgent => 'CB Agent';
  @override
  String get cbAgentTitle => 'CB Agent';
  @override
  String get cbAgentSubtitle => 'CB File Hub için yerleşik yapay zeka asistanı';

  // Disk Cleaner (CB Agent skill)
  @override
  String get cbAgentCleanerTitle => 'Disk Temizleyici (CB Agent)';
  @override
  String get diskCleanerNotAvailable =>
      'Disk Temizleyici Windows ve macOS\'ta kullanılabilir';
  @override
  String get diskCleanerScanTitle => 'Gereksiz dosyaları tara';
  @override
  String get diskCleanerScanRunning => 'Taranıyor...';
  @override
  String get diskCleanerScanDone => 'Tarama tamamlandı';
  @override
  String get diskCleanerCleanTitle => 'Gereksiz dosyaları temizle';
  @override
  String get diskCleanerCleanDone => 'Temizlik tamamlandı';
  @override
  String get diskCleanerAskAgent => 'CB Agent\'a sor';

  @override
  String get diskCleanerSuggestAndSelect => 'Hızlı inceleme';
  @override
  String get diskCleanerQuickReviewHint =>
      'Her grubu tarama meta verileriyle açıklar; yapay zeka yalnızca belirsiz birkaçına bakar.';
  @override
  String get diskCleanerFullAiReview => 'Tam yapay zeka incelemesi';
  @override
  String get diskCleanerFullAiReviewHint =>
      'Yapay zeka her grubu, en büyükten başlayarak değerlendirir. Yerel modelde yavaştır; istediğiniz an durdurup sürdürebilirsiniz.';
  @override
  String get diskCleanerFullAiReviewRequest =>
      'Tarama sonuçlarındaki her grubu en büyükten başlayarak yapay zekayla incele: veri nedir, '
      'saklanmalı mı yoksa kaldırılabilir mi. Dosya içeriklerini okuma, dosya seçme veya '
      'hiçbir şeyi silme. Türkçe yanıt ver.';
  @override
  String get diskCleanerStopAiReview => 'Yapay zeka incelemesini durdur';
  @override
  String get diskCleanerAiReviewOptions => 'Yapay zeka inceleme seçenekleri';
  @override
  String get diskCleanerSelectionMenu => 'Seç';
  @override
  String get diskCleanerAiNeedsFreshScan =>
      'Kayıtlı sonuçlar gösteriliyor. Yapay zekanın güncel diski incelemesi için yeniden tarayın.';
  @override
  String get diskCleanerAiWaitForScan =>
      'Yapay zeka incelemesi için taramanın bitmesini bekleyin.';
  @override
  String get diskCleanerAiWaitForCleanup =>
      'Yapay zekaya sormadan önce mevcut temizlik incelemesini bitirin.';
  @override
  String diskCleanerAiReviewProgress(int percent) => 'AI %$percent';
  @override
  String get diskCleanerDashboardTitle => 'Genel bakış';
  @override
  String get diskCleanerDashboardHint =>
      'Ayrıntıları görmek ve filtrelemek için bir kart seçin.';
  @override
  String get diskCleanerDashboardHeavyFolders => 'Büyük klasörler';
  @override
  String get diskCleanerDashboardLargeFiles => 'Büyük dosyalar';
  @override
  String get diskCleanerDashboardOldUnused => 'Eski ve kullanılmayan';
  @override
  String get diskCleanerDashboardKnownCauses => 'Bilinen alan tüketiciler';
  @override
  String get diskCleanerDashboardFileTypes => 'Dosya türüne göre';
  @override
  String get diskCleanerDashboardAllTypes => 'Tüm türler';
  @override
  String get diskCleanerDashboardNoMatches => 'Bu koşullara uyan öğe yok.';
  @override
  String diskCleanerDashboardCount(int count) => '$count öğe';
  @override
  String diskCleanerDashboardAtLeast(String size) => 'En az $size';
  @override
  String diskCleanerDashboardUnusedFor(String age) => '$age+ kullanılmadı';
  @override
  String diskCleanerDashboardMonths(int months) => '$months ay';
  @override
  String diskCleanerDashboardYears(int years) => '$years yıl';
  @override
  String diskCleanerDashboardOfDisk(String percent) => 'diskin $percent';
  @override
  String diskCleanerFileTypeLabel(String group) => switch (group) {
    'video' => 'Videolar',
    'disk_image' => 'Disk görüntüleri (ISO, VHD…)',
    'archive' => 'Arşivler',
    'installer' => 'Yükleyiciler',
    'ai_model' => 'Yapay zeka modelleri',
    'database_mail' => 'Veritabanı ve posta',
    'audio' => 'Ses',
    'image_raw' => 'RAW ve tasarım görselleri',
    'dump_log' => 'Döküm ve günlükler',
    'game_data' => 'Oyun verileri',
    'other' => 'Diğer dosyalar',
    _ => group,
  };
  @override
  String get diskCleanerAdviceFromScan => 'Tarama meta verilerine dayalı';
  @override
  String get diskCleanerAdviceFromAi => 'Yapay zeka önerisi';

  @override
  String get diskCleanerAiSelectRecommendationsRequest =>
      'Tarama meta verilerinden hızlı bir genel bakış ver: verilerin ne olduğu ve '
      'saklanması mı yoksa kaldırılmasının düşünülmesi mi gerektiği. '
      'Kısa grup açıklamaları kullan; yalnızca az sayıda belirsiz grubu yapay zekayla incele. '
      'Dosya içeriklerini okuma, dosya seçme veya herhangi bir şey silme. Türkçe yanıtla.';
  @override
  String get diskCleanerAgentAnalysisTitle => 'CB Agent analizi';
  @override
  String diskCleanerAgentGroupCount(int count) =>
      '$count girdi birlikte değerlendirildi';
  @override
  String get diskCleanerAgentInspecting => 'CB Agent bu öğeyi inceliyor';
  @override
  String get diskCleanerAgentCanClean => 'Temizlenebilir';
  @override
  String get diskCleanerAgentNeedsReview => 'Önce gözden geçir';
  @override
  String get diskCleanerAgentKeep => 'Sakla';
  @override
  String get diskCleanerAiInspectItemRequest =>
      'get_current_cleaner_scan çıktısını oku, ardından inspect_cleaner_scan_item ile '
      'bu yolu tam olarak incele ve değerlendirmeni select:false ile '
      'set_cleaner_scan_item_analysis kullanarak tarama ekranında göster. '
      'Temizlenmesi, gözden geçirilmesi veya saklanması gerektiğini açıkla. Türkçe yanıtla.';
  @override
  String get diskCleanerMoveToRecycleBin => 'Geri Dönüşüm Kutusu\'na taşı';
  @override
  String get diskCleanerPermanentDelete => 'Kalıcı olarak sil';
  @override
  String get diskCleanerSelectCategories => 'Kategorileri seç';
  @override
  String get diskCleanerSelectDrives => 'Sürücüleri seç';
  @override
  String get diskCleanerScanAgain => 'Yeniden tara';
  @override
  String get diskCleanerCachedResultStatus =>
      'Önceki tarama gösteriliyor (önbelleğe alınmış sonuç). Yenilemek için yeniden tarayın.';

  // Disk Cleaner — extended UI strings
  @override
  String get diskCleanerCancel => 'İptal';
  @override
  String get diskCleanerShowCleanableOnly =>
      'Yalnızca temizlenebilirleri göster';
  @override
  String diskCleanerCleanableOnlyChip(int count) =>
      'Yalnızca temizlenebilir ($count)';
  @override
  String get diskCleanerCheckAllCleanable =>
      'Temizlenebilirlerin tümünü işaretle';
  @override
  String get diskCleanerUncheckAll => 'Tüm işaretleri kaldır';

  @override
  String get diskCleanerColumnName => 'Ad';
  @override
  String get diskCleanerColumnSize => 'Boyut';
  @override
  String get diskCleanerColumnPercentOfParent => 'Üstün %\'si';
  @override
  String get diskCleanerColumnFiles => 'Dosyalar';
  @override
  String get diskCleanerBuildingTree => 'Disk ağacı oluşturuluyor...';
  @override
  String get diskCleanerNoFilesFound => 'Dosya bulunamadı';
  @override
  String get diskCleanerAnalyzingDisk => 'Disk kullanımı analiz ediliyor...';
  @override
  String get diskCleanerPieChartPending =>
      'Pasta grafik tarama tamamlandıktan sonra görünecek.';
  @override
  String get diskCleanerPieEmpty => 'Boş';
  @override
  String get diskCleanerPreparingFiles => 'Dosyalar hazırlanıyor...';
  @override
  String get diskCleanerCleaning => 'Temizleniyor...';
  @override
  String get diskCleanerScanningSelectedDirs => 'Seçilen dizinler taranıyor...';
  @override
  String get diskCleanerDeletingJunkHint =>
      'Seçilen öğeler siliniyor. Bir dosya başarısız olursa atlayabilir veya yeniden deneyebilirsiniz.';
  @override
  String get diskCleanerPermanentDeleteLabel => 'Kalıcı olarak sil';
  @override
  String get diskCleanerRecycleBinLabel => 'Geri Dönüşüm Kutusu';
  @override
  String get diskCleanerDeletingItems => 'Öğeler siliniyor...';
  @override
  String get diskCleanerReviewMode => 'İnceleme modu';
  @override
  String get diskCleanerBackToResults => 'Sonuçlara dön';
  @override
  String get diskCleanerReviewByAgent => 'CB Agent incelemesi';
  @override
  String get diskCleanerPermanentlyDeleting => 'Kalıcı olarak siliniyor...';
  @override
  String get diskCleanerMovingToRecycleBin =>
      'Geri Dönüşüm Kutusu\'na taşınıyor...';
  @override
  String get diskCleanerWaitingDecision => 'Kararınız bekleniyor...';
  @override
  String get diskCleanerFileInUse =>
      'Bu dosya başka bir uygulama tarafından kullanılıyor gibi görünüyor.';
  @override
  String get diskCleanerRetryInUseHint =>
      'Bu dosyayı kullanan uygulama veya işlem kapatılmadan yeniden denemek genellikle yine başarısız olur.';
  @override
  String get diskCleanerBlockedBy => 'Engelleyen:';
  @override
  String get diskCleanerSkipAllRemaining => 'Kalan tüm öğeleri atla';
  @override
  String get diskCleanerSkip => 'Atla';
  @override
  String get diskCleanerTryAgain => 'Yeniden dene';
  @override
  String get diskCleanerProtectedLabel => 'Silinemez';
  @override
  String get diskCleanerProtectedReason =>
      'Bu öğe temel sistem verileri içerir veya bu verilere aittir. CB Cleaner, yönetici erişimi kullanılırken bile bu öğeyi korur. Disk kullanımını inceleyebilirsiniz.';
  @override
  String get diskCleanerPermanentDeleteConfirmTitle =>
      'Kalıcı olarak silinsin mi?';
  @override
  String diskCleanerPermanentDeleteFromBinContent(int count, String size) =>
      'Bu işlem, Geri Dönüşüm Kutunuzdaki $count öğeyi ($size) kalıcı olarak silecek. Bundan sonra geri yüklenemezler.';
  @override
  String diskCleanerPermanentDeleteSelectedContent(int count, String size) =>
      'Bu işlem, seçilen $count öğeyi ($size) kalıcı olarak silecek. Bundan sonra geri yüklenemezler.';
  @override
  String get diskCleanerColumnFileName => 'Dosya adı';
  @override
  String get diskCleanerColumnPath => 'Yol';
  @override
  String get diskCleanerColumnCategory => 'Kategori';
  @override
  String get diskCleanerRecycleBinEmpty =>
      'Geri Dönüşüm Kutusu\'nda şu anda öğe yok.';
  @override
  String diskCleanerItemsInRecycleBin(int count, String size) =>
      'Geri Dönüşüm Kutusu\'nda $count öğe ($size)';
  @override
  String diskCleanerSkippedInUseSnack(int count) =>
      'Şu anda kullanımda olan $count dosya atlandı. Ayrıntılar günlüğe kaydedildi.';
  @override
  String diskCleanerSkippedAfterFailureSnack(int count) =>
      'Silme başarısız olduktan sonra $count dosya atlandı.';
  @override
  String diskCleanerFreedBadge(String size, int count) =>
      '$size boşaltıldı  •  $count öğe';
  @override
  String diskCleanerFailedBadge(int count) => '$count başarısız';
  @override
  String diskCleanerInUseBadge(int count) => '$count kullanımda';
  @override
  String diskCleanerSkippedBadge(int count) => '$count atlandı';
  @override
  String diskCleanerSkippedInUseBanner(int count) =>
      'Şu anda kullanımda olan $count dosya atlandı. Tam yol listesi için günlüklere bakın.';
  @override
  String diskCleanerSkippedByUserBanner(int count) =>
      'Atla\'yı seçtiğiniz için silme başarısız olduktan sonra $count dosya atlandı.';
  @override
  String diskCleanerDeletedPermanentlyBody(int count) =>
      '$count öğe kalıcı olarak silindi.';
  @override
  String diskCleanerFreedSpace(String size) => '$size boşaltıldı';
  @override
  String diskCleanerPermanentDeleteFinished(int count) =>
      '$count öğe için kalıcı silme tamamlandı.';
  @override
  String diskCleanerPermanentDeletingProgress(int done, int total) =>
      'Kalıcı olarak siliniyor... $done / $total';
  @override
  String get diskCleanerDeletingLabel => 'Siliniyor...';
  @override
  String get diskCleanerRemaining => 'kaldı';
  @override
  String diskCleanerDriveFree(String label, String size) => '$label  $size boş';
  @override
  String diskCleanerFilesCount(int count) => '$count dosya';
  @override
  String diskCleanerDirsCount(int count) => '$count dizin';
  @override
  String get diskCleanerStarting => 'Başlatılıyor...';
  @override
  String diskCleanerDriveSummary(String path, String size, int count) =>
      '$path  $size  •  $count dosya';
  @override
  String get diskCleanerGrowthTitle => 'Son zamanlarda büyüyen klasörler';
  @override
  String diskCleanerGrowthFilter(int count) =>
      'Son zamanlarda büyüyenler ($count)';
  @override
  String diskCleanerGrowthIncrease(String size) => '+$size';
  @override
  String diskCleanerGrowthCurrentSize(String size) => 'Geçerli boyut: $size';
  @override
  String diskCleanerAgentPath(String path) => 'CB Agent: $path';
  @override
  String diskCleanerItemsBytes(int count, String size) => '$count öğe • $size';
  @override
  String diskCleanerSizeFiles(String size, int files) => '$size • $files dosya';

  @override
  String diskCleanerRolledUpItems(int items) => '$items daha küçük öğe';
  @override
  String diskCleanerScannedProgress(String size, int files) =>
      '$size tarandı • $files dosya';
  @override
  String get diskCleanerPieChartPendingScan =>
      'Pasta grafik tarama tamamlanır tamamlanmaz görünecek';
  @override
  String get diskCleanerIncrementalScanTitle => 'Artımlı tarama';
  @override
  String diskCleanerIncrementalScanProgress(int count) =>
      'Değişen $count klasör güncellendi';
  @override
  String get diskCleanerFullScanFallback =>
      'Artımlı tarama kullanılamıyor — tam tarama tamamlandı';
  @override
  String get diskCleanerOldLargeTitle => 'Eski ve büyük öğeler';
  @override
  String get diskCleanerOldLargeSubtitle =>
      'Yalnızca inceleme ipuçları. Dosya sistemi zaman damgaları bir öğenin kullanılmadığını kanıtlamaz.';
  @override
  String get diskCleanerOldLargeAll => 'Tümü';
  @override
  String get diskCleanerOldLargeFiles => 'Dosyalar';
  @override
  String get diskCleanerOldLargeFolders => 'Klasörler';
  @override
  String diskCleanerOldLargeLastActivity(String date) =>
      'Son etkinlik ipucu: $date';
  @override
  String get diskCleanerOldLargeReviewOnly => 'Yalnızca inceleme';
  @override
  String get diskCleanerOldLargeEmpty =>
      'Eski ve büyük dosya veya klasör bulunamadı.';
  @override
  String diskCleanerScanningPath(String path) => '$path taranıyor';
  @override
  String diskCleanerProcessedCount(int done, int total) =>
      '$done / $total işlendi';
  @override
  String diskCleanerJunkSummary(String size) => 'Gereksiz: $size';
  @override
  String get diskCleanerContinue => 'Devam';
  @override
  String get diskCleanerAiPanelUnavailable =>
      'Yapay zeka paneli bu bağlamda kullanılamıyor';
  @override
  String get diskCleanerAskAgentAboutThis => 'CB Agent\'a bunu sor';
  @override
  String get diskCleanerAiDeleteAnalysisIntro =>
      'Lütfen bu dosyayı veya klasörü silip silmemem gerektiğini analiz et:';
  @override
  String get diskCleanerAiLabelPath => 'Yol';
  @override
  String get diskCleanerAiLabelType => 'Tür';
  @override
  String get diskCleanerAiLabelName => 'Ad';
  @override
  String get diskCleanerAiLabelSize => 'Boyut';
  @override
  String get diskCleanerAiLabelFiles => 'Dosyalar';
  @override
  String get diskCleanerAiTypeFile => 'Dosya';
  @override
  String get diskCleanerAiTypeFolder => 'Klasör';
  @override
  String diskCleanerAiCategoryMarkedJunk(String category) =>
      'Kategori: $category (gereksiz olarak işaretlendi)';
  @override
  String get diskCleanerAiNotMarkedAsJunk =>
      'Kurallara göre gereksiz olarak işaretlenmedi.';
  @override
  String get diskCleanerAiDeleteAnalysisQuestion =>
      'Bu dosya veya klasörün büyük olasılıkla ne için kullanıldığını, silmenin güvenli olup olmadığını, hangi riskleri göz önünde bulundurmam gerektiğini açıkla ve net bir öneri ver: sil, sakla veya elle incele. Türkçe yanıtla.';
  @override
  String diskCleanerScanFailedMsg(String error) => 'Tarama başarısız: $error';
  @override
  String diskCleanerCleanupFailedMsg(String error) =>
      'Temizlik başarısız: $error';
  @override
  String diskCleanerPermanentDeleteFailedMsg(String error) =>
      'Kalıcı silme başarısız: $error';
  @override
  String diskCleanerAgentFoundJunk(int count, String size) =>
      'CB Agent $count gereksiz öğe buldu ($size)';
  @override
  String diskCleanerAndMoreItems(int count) => '... ve $count öğe daha';
  @override
  String diskCleanerSelectedBytes(String size, String total) =>
      'Seçilen: $size / $total';
  @override
  String diskCleanerReviewModeSelected(String size) =>
      'İnceleme modu • Seçilen: $size';
  @override
  String diskCleanerDeletePermanentlyButton(String size) =>
      '$size kalıcı olarak sil';
  @override
  String diskCleanerMoveToRecycleBinButton(String size) =>
      '$size Geri Dönüşüm Kutusu\'na taşı';
  @override
  String diskCleanerReviewAndClean(String size) => '$size incele ve temizle';
  @override
  String diskCleanerPermanentDeletedSuccess(int count, String size) =>
      '$count öğe kalıcı olarak silindi ($size)';
  @override
  String diskCleanerPermanentDeletedWithInUse(
    int count,
    String size,
    int skipped,
  ) =>
      '$count öğe kalıcı olarak silindi ($size). Kullanımda olan $skipped dosya atlandı; ayrıntılar günlüğe kaydedildi.';
  @override
  String diskCleanerPermanentDeletedWithSkipped(
    int count,
    String size,
    int skipped,
  ) =>
      '$count öğe kalıcı olarak silindi ($size). Silme başarısız olduktan sonra $skipped dosya atlandı.';

  // Cleaner - drive picker, quick clean, junk reasons
  @override
  String get diskCleanerDriveLowSpace => 'Düşük alan';
  @override
  String diskCleanerDriveCapacity(String used, String total, String free) =>
      '$total içinde $used kullanıldı · $free boş';
  @override
  String diskCleanerLastScanFound(String when, String junk) =>
      'Son tarama $when · $junk gereksiz bulundu';
  @override
  String get diskCleanerTimeJustNow => 'az önce';
  @override
  String get diskCleanerTimeToday => 'bugün';
  @override
  String get diskCleanerTimeYesterday => 'dün';
  @override
  String diskCleanerTimeDaysAgo(int days) => '$days gün önce';
  @override
  String diskCleanerTimeWeeksAgo(int weeks) =>
      weeks == 1 ? 'bir hafta önce' : '$weeks hafta önce';
  @override
  String diskCleanerTimeMonthsAgo(int months) =>
      months <= 1 ? 'bir ay önce' : '$months ay önce';
  @override
  String get diskCleanerQuickCleanHint =>
      'Eski geçici dosyalar, tarayıcı ve uygulama önbellekleri, çökme raporları. Uygulamalar bunları gerektiğinde yeniden oluşturur.';
  @override
  String get diskCleanerQuickCleanButton => 'Hızlı temizlik';
  @override
  String get diskCleanerQuickCleanNothing =>
      'Şu anda temizlenecek güvenli bir şey yok';
  @override
  String get diskCleanerQuickCleanRecycleNote =>
      'Her şey Geri Dönüşüm Kutusu\'na gider, böylece oradan geri yükleyebilirsiniz.';
  @override
  String get diskCleanerQuickCleanSafetyNote =>
      'Yalnızca bir gündür değişmeyen dosyalar; geçici dosyalar, gölgelendirici ve paket önbellekleri için bir hafta. Önce uygulamaları kapatıp kurulum ve derlemeleri bitirin. Kilitli dosyalar atlanır.';
  @override
  String get cleanerSmartCleanTitle => 'Akıllı Temizlik';
  @override
  String get cleanerSmartCleanUtilityDescription =>
      'Tek tıkla güvenli gereksiz dosyalar';
  @override
  String get cleanerSmartCleanIntro =>
      'Eski geçici dosyaları, sistem ve Electron önbelleklerini, paket indirmelerini ve çökme raporlarını bulur. Yeniden oluşturulacak veya indirilecekleri gösterir. Belgeler, ayarlar ve kurulu kitaplıklar korunur.';
  @override
  String get cleanerSmartCleanScan => 'Tara';
  @override
  String cleanerSmartCleanScanningCategory(String category) =>
      '$category denetleniyor...';
  @override
  String get cleanerSmartCleanPreparing => 'Hazırlanıyor...';
  @override
  String cleanerSmartCleanItemCount(int count) => '$count öğe';
  @override
  String cleanerSmartCleanCleanButton(String size) => '$size temizle';
  @override
  String get cleanerSmartCleanAllCleanTitle => 'Cihazınız düzenli';
  @override
  String get cleanerSmartCleanPermanentBadge => 'Kalıcı';
  @override
  String get cleanerSmartCleanRecycleBinWarning =>
      "Varsayılan olarak seçili değil. Geri Dönüşüm Kutusu'ndaki öğeler kalıcı olarak silinir ve geri yüklenemez.";
  @override
  String cleanerSmartCleanMoreItems(int count) => 've $count öğe daha';
  @override
  String get cleanerSmartCleanDoneTitle => 'Temizlik tamamlandı';
  @override
  String cleanerSmartCleanDoneMoved(String size, String destination) =>
      '$size, $destination konumuna taşındı';
  @override
  String cleanerSmartCleanDonePermanent(String size) =>
      "Geri Dönüşüm Kutusu'ndan $size kalıcı olarak silindi";
  @override
  String cleanerSmartCleanDoneSkipped(int count) =>
      'Kullanımda olan veya kaldırılamayan $count öğe atlandı.';
  @override
  String cleanerSmartCleanDoneHint(String destination) =>
      '$destination boşaltıldığında disk alanı tamamen boşalır.';
  @override
  String get cleanerSmartCleanBusy =>
      'Başka bir tarama sürüyor. Bittiğinde yeniden deneyin.';
  @override
  String get cleanerSmartCleanPermanentConfirmTitle =>
      'Geri Dönüşüm Kutusu boşaltılsın mı?';
  @override
  String cleanerSmartCleanPermanentConfirmBody(String size) =>
      "Geri Dönüşüm Kutusu'ndaki $size kalıcı olarak silinecek. Seçilen diğer öğeler her zamanki gibi Geri Dönüşüm Kutusu'na taşınır.";
  @override
  String get cleanerSmartCleanConfirmClean => 'Temizle';
  @override
  String cleanerSmartCleanReclaimable(String size) =>
      '$size güvenli gereksiz dosya bulundu';
  @override
  String cleanerSmartCleanSelected(String size, int count) =>
      '$size seçildi ($count öğe)';
  @override
  String get cleanerSmartCleanChecksLabel => 'Denetlenenler';
  @override
  String cleanerSmartCleanMostlyFrom(String apps) => 'Çoğu $apps kaynaklı';
  @override
  String get cleanerSmartCleanUnknownApp => 'Bilinmeyen uygulama';
  @override
  String cleanerSmartCleanFolderSource(String folder) => '"$folder" klasörü';
  @override
  String cleanerSmartCleanOtherSources(int count) => '$count diğer kaynak';
  @override
  String get cleanerSmartCleanKindWebCache => 'Web önbelleği';
  @override
  String get cleanerSmartCleanKindCodeCache => 'Derlenmiş betik önbelleği';
  @override
  String get cleanerSmartCleanKindGpuCache => 'GPU gölgelendirici önbelleği';
  @override
  String get cleanerSmartCleanKindAppCache => 'Uygulama önbelleği';
  @override
  String get cleanerSmartCleanKindThumbnailCache => 'Küçük resim veritabanı';
  @override
  String get cleanerSmartCleanKindTempFile => 'Geçici dosyalar';
  @override
  String get cleanerSmartCleanKindInstaller => 'Yükleyici artıkları';
  @override
  String get cleanerSmartCleanKindLog => 'Günlükler';
  @override
  String get cleanerSmartCleanKindCrashReport => 'Çökme raporları';
  @override
  String get cleanerSmartCleanKindDeletedFile => 'Silinmiş dosyalar';
  @override
  String get cleanerSmartCleanKindOther => 'Diğer dosyalar';
  @override
  String get cleanerSmartCleanKindWebCacheInfo =>
      'Önceden indirilmiş sayfalar, görseller ve medya. Gerektiğinde yeniden indirilir; siteler ilk açılışta biraz yavaş yüklenebilir.';
  @override
  String get cleanerSmartCleanKindCodeCacheInfo =>
      'Uygulamanın önceden derlediği betikler. Uygulama bir sonraki açılışta yeniden derler.';
  @override
  String get cleanerSmartCleanKindGpuCacheInfo =>
      'GPU için derlenmiş grafik gölgelendiricileri. Bir sonraki açılışta yeniden oluşturulur.';
  @override
  String get cleanerSmartCleanKindAppCacheInfo =>
      'Uygulamanın daha hızlı açılmak için tuttuğu veriler. Gerektiğinde yeniden indirir veya oluşturur.';
  @override
  String get cleanerSmartCleanKindThumbnailCacheInfo =>
      'Dosya Gezgini’nin resim ve videolar için gösterdiği önizlemeler. Klasörleri açtıkça Windows yeniden oluşturur.';
  @override
  String get cleanerSmartCleanKindTempFileInfo =>
      'Uygulamanın işi bitince bıraktığı geçici dosyalar. Artık hiçbir şey bunları okumaz.';
  @override
  String get cleanerSmartCleanKindInstallerInfo =>
      'Kurulum veya güncelleme sırasında açılan paketler. Yeniden kurulumda tekrar indirilir.';
  @override
  String get cleanerSmartCleanKindLogInfo =>
      'Uygulamanın yaptıklarının kaydı. Yalnızca bir sorunu giderirken işe yarar.';
  @override
  String get cleanerSmartCleanKindCrashReportInfo =>
      'Uygulama çöktüğünde veya donduğunda kaydedilir. Yalnızca geliştiriciye göndermeyi planlıyorsanız saklayın.';
  @override
  String get cleanerSmartCleanKindDeletedFileInfo =>
      'Daha önce sildiğiniz dosyalar. Geri Dönüşüm Kutusu’nu boşaltmak onları kalıcı olarak kaldırır.';
  @override
  String get cleanerSmartCleanKindOtherInfo =>
      'Birçok uygulamadan küçük miktarlar; her biri ayrı listelenemeyecek kadar küçük.';
  @override
  String get cleanerSmartCleanImpactRebuilt => 'Kendiliğinden yeniden oluşur';
  @override
  String get cleanerSmartCleanImpactLeftover => 'Artık kullanılmıyor';
  @override
  String get cleanerSmartCleanImpactDiagnostic => 'Yalnızca sorun giderme için';
  @override
  String get cleanerSmartCleanImpactPermanent => 'Geri yüklenemez';
  @override
  String get cleanerSmartCleanInstalledBadge => 'Yüklü';
  @override
  String get diskCleanerCategoryWindowsTemp => 'Windows geçici dosyaları';
  @override
  String get diskCleanerCategoryBrowserCache => 'Tarayıcı önbellekleri';
  @override
  String get diskCleanerCategoryRecycleBin => 'Geri Dönüşüm Kutusu';
  @override
  String get diskCleanerCategoryThumbnailCache => 'Küçük resim önbelleği';
  @override
  String get diskCleanerCategoryAppCache => 'Uygulama önbellekleri';
  @override
  String get diskCleanerCategoryCrashLogs => 'Çökme dökümleri ve günlükler';
  @override
  String get diskCleanerCategoryWindowsUpdate => 'Windows Update önbelleği';
  @override
  String get diskCleanerCategoryPrefetch => 'Prefetch verileri';
  @override
  String get diskCleanerCategoryDeliveryOptimization =>
      'Teslim Optimizasyonu dosyaları';
  @override
  String get diskCleanerCategoryDevCache => 'Geliştirici önbellekleri';
  @override
  String get diskCleanerCategorySystemCache =>
      'Windows gölgelendirici önbelleği';
  @override
  String get diskCleanerCategoryPackageDownloads =>
      'Paket indirme önbellekleri';
  @override
  String get diskCleanerCategoryElectronCache =>
      'Electron uygulama önbellekleri';
  @override
  String get diskCleanerReasonSystemCache =>
      'Bir haftadan eski DirectX gölgelendirici önbelleği. Yeniden derleme sırasında oyunlar yavaşlayabilir. Temizlemeden önce oyunları kapatın.';
  @override
  String get diskCleanerReasonPackageDownloads =>
      'Bir haftadan eski npm, pip, Cargo, NuGet HTTP ve Composer indirme önbellekleri. Sonraki kurulumda internet ve yeniden indirme/derleme gerekebilir. Kurulu kitaplıklar korunur. Önce kurulum ve derlemelerin bitmesini bekleyin.';
  @override
  String get diskCleanerReasonElectronCache =>
      'Desteklenen Electron uygulamalarının web, JavaScript ve GPU önbellekleri. Önce uygulamaları kapatın. Parolalar, ayarlar, IndexedDB ve çevrimdışı veriler korunur.';
  @override
  String get cleanerSmartCleanImpactRedownload => 'Yeniden indirebilir';
  @override
  String get diskCleanerCategoryXcodeBuild => 'Eski Xcode derleme dosyaları';
  @override
  String get diskCleanerReasonXcodeBuild =>
      'En az 7 gündür değişmeyen derleme çıktıları, ara dosyalar, indeksler ve modül önbellekleri. Önce Xcode uygulamasını kapatıp derlemeleri durdurun. Kaynaklar, paketler, arşivler ve dSYM korunur. Sonraki derleme ve indeksleme uzayabilir.';
  @override
  String get cleanerOldFilesTitle => 'Eski indirmeler — yalnızca inceleme';
  @override
  String get cleanerOldFilesDescription =>
      'Varsayılan Downloads klasöründe en az 90 gündür değişmeyen en büyük 200 dosya. Değişiklik tarihi son açılış değildir ve kullanılmadığını kanıtlamaz. Bu dosyalar temizlik için seçilmez. İncelemek için klasörü açın.';
  @override
  String cleanerOldFilesCount(int count) => 'İncelenecek $count dosya';
  @override
  String cleanerOldFilesModified(String date) => 'Son değişiklik: $date';
  @override
  String get cleanerOldFilesShowMore => 'Daha fazla dosya göster';
  @override
  String get diskCleanerReasonWindowsTemp =>
      'Uygulamalar tarafından geride bırakıldı. Kaldırmak güvenlidir; hiçbir şey buna bağlı değildir.';
  @override
  String get diskCleanerReasonBrowserCache =>
      'Tarayıcınız bunu gerektiğinde yeniden oluşturur. Sayfalar bir kez biraz daha yavaş yüklenebilir.';
  @override
  String get diskCleanerReasonRecycleBin =>
      'Boşaltılmayı bekleyen, zaten silinmiş dosyalar.';
  @override
  String get diskCleanerReasonThumbnailCache =>
      'Windows, bir sonraki klasör açışınızda küçük resimleri yeniden oluşturur.';
  @override
  String get diskCleanerReasonAppCache =>
      'Geçici uygulama verileri. Uygulamalar bunları yeniden oluşturur; oturumunuz açık kalır.';
  @override
  String get diskCleanerReasonCrashLogs =>
      'Geçmiş çökmelerden kalan tanılama dosyaları. Yalnızca sorun gidermede işe yarar.';
  @override
  String get diskCleanerReasonWindowsUpdate =>
      'Zaten uygulanmış güncellemelerin yükleyicileri.';
  @override
  String get diskCleanerReasonPrefetch =>
      'Uygulama başlatma ipuçları. Windows bunları sonraki birkaç başlatmada yeniden oluşturur.';
  @override
  String get diskCleanerReasonDeliveryOptimization =>
      'Ağınızdaki diğer bilgisayarlarla paylaşmak için önbelleğe alınmış güncelleme dosyaları.';
  @override
  String get diskCleanerReasonDevCache =>
      'Derleme ve paket önbellekleri. Araçlarınız bunları yeniden indirir veya oluşturur.';
  @override
  String get diskCleanerReasonGeneric =>
      'Bilinen bir gereksiz dosya konumuyla eşleşti ve kaldırması güvenli.';

  // Cleaner - tree preset views
  @override
  String get diskCleanerPresetTooltip => 'Ağacı filtrele';
  @override
  String get diskCleanerPresetAll => 'Her şey';
  @override
  String get diskCleanerPresetLargeFiles => '1 GB üzeri dosyalar';
  @override
  String get diskCleanerPresetLogsCaches => 'Günlükler ve önbellekler';
  @override
  String get diskCleanerPresetInstallers => 'Yükleyiciler ve arşivler';

  // Cleaner - cleaned screen outcome
  @override
  String diskCleanerFreeSpaceBeforeAfter(String before, String after) =>
      'Boş alan: $before → $after';
  @override
  String get diskCleanerGrowthWatchTitle => 'Son taramanızdan beri büyüyenler';
  @override
  String diskCleanerGrowthWatchLine(String path, String size) =>
      '$path  +$size';

  // Cleaner App Insights
  @override
  String get cleanerUtilitiesTitle => 'CB Agent Temizleyici';
  @override
  String get cleanerUtilitiesSubtitle =>
      'Bu bilgisayarı hızlı ve düzenli tutmanıza yardımcı olan araçlar';
  @override
  String get cleanerUtilitiesStorageGroup => 'Depolama';
  @override
  String get cleanerDiskUsageTitle => 'Disk kullanımı';
  @override
  String get cleanerDiskUtilityDescription =>
      'Klasörleri inceleyin ve onaylanmış gereksiz dosyaları güvenle temizleyin';
  @override
  String get cleanerAppsTitle => 'Uygulamalar';
  @override
  String get cleanerAppsUtilityDescription =>
      'Büyük veya nadiren kullanılan uygulamaları bulun ve verilerini inceleyin';

  // Cleaner - space usage causes (Disk usage dashboard)
  @override
  String cleanerSuggestionTitle(String id) => switch (id) {
    'downloads_leftovers' => 'İndirilenler\'deki eski yükleyiciler ve arşivler',
    'old_large_files' => 'Uzun süredir kullanılmayan büyük dosyalar',
    'node_modules' => 'node_modules klasörleri',
    'hibernation_file' => 'Hazırda bekletme dosyası',
    'previous_windows' => 'Önceki Windows kurulumu',
    'wsl_disk' => 'WSL Linux diski',
    'docker_data' => 'Docker Desktop verileri',
    'virtual_machine_disk' => 'Sanal makine diskleri',
    'game_library' => 'Yüklü oyunlar',
    'phone_backup' => 'iPhone / iPad yedekleri',
    'android_dev' => 'Android SDK ve emülatörler',
    'ai_models' => 'İndirilen yapay zeka modelleri',
    _ => id,
  };
  @override
  String cleanerSuggestionDetail(String id) => switch (id) {
    'downloads_leftovers' =>
      '30+ gündür dokunulmamış yükleyiciler, disk görüntüleri ve arşivler. '
          'Genellikle yalnızca bir kez gerekirler.',
    'old_large_files' =>
      'Yakın zamanda etkinliği olmayan kendi büyük dosyalarınız. Eski olması '
          'gereksiz olduğu anlamına gelmez: emin değilseniz başka bir sürücüye taşıyın.',
    'node_modules' =>
      'JavaScript bağımlılıkları. Artık üzerinde çalışmadığınız projelerden '
          'kaldırın; "npm install" bunları geri getirir.',
    'hibernation_file' =>
      'Hazırda bekletme ve Hızlı Başlangıç için belleği saklar. Hazırda '
          'bekletmeyi kullanmıyorsanız kaldırmak için yönetici terminalinde '
          '"powercfg /h off" çalıştırın.',
    'previous_windows' =>
      'Geri dönebilmeniz için Windows yükseltmesinden sonra saklanır. '
          'Yükseltme kararlı olduğunda Depolama > Geçici dosyalar bölümünden kaldırın.',
    'wsl_disk' =>
      'Kendiliğinden küçülmeyen Linux sanal diski. Linux içindeki dosyaları '
          'silin, "wsl --shutdown" çalıştırın, ardından diski sıkıştırın.',
    'docker_data' =>
      'İmajlar, kapsayıcılar ve derleme önbelleği. "docker system df" ile '
          'kontrol edin ve artık gerekmeyenleri temizleyin.',
    'virtual_machine_disk' =>
      'Sanal makine diskleri. Kullanılmayan sanal makineleri sanal makine '
          'yöneticisinden kaldırın.',
    'game_library' =>
      'Artık oynamadığınız oyunları başlatıcısından kaldırın; yeniden '
          'indirilebilirler.',
    'phone_backup' =>
      'Apple Cihazlar / iTunes cihaz yedekleri. Eski yedekleri uygulamadan silin.',
    'android_dev' =>
      'Kullanılmayan sistem görüntülerini ve emülatörleri Android Studio\'dan kaldırın.',
    'ai_models' =>
      'Ollama veya LM Studio gibi araçlardan model dosyaları. Artık '
          'kullanmadığınız modelleri araçtan kaldırın.',
    _ => '',
  };
  @override
  String get cleanerAppsLoading => 'Yüklü uygulamalar analiz ediliyor...';
  @override
  String get cleanerAppsUnavailable =>
      'Uygulama içgörüleri disk taraması tamamlandıktan sonra kullanılabilir olacak.';
  @override
  String cleanerAppsLoadFailed(String error) =>
      'Yüklü uygulamalar analiz edilemedi: $error';
  @override
  String get cleanerAppsPartialBanner => 'Sonuçlar hâlâ güncelleniyor.';
  @override
  String get cleanerAppsSearchHint => 'Uygulama ara';
  @override
  String get cleanerAppsFilterAll => 'Tümü';
  @override
  String get cleanerAppsFilterAttention => 'İncele';
  @override
  String get cleanerAppsFilterLarge => 'Büyük';
  @override
  String get cleanerAppsFilterStale => 'Nadiren kullanılan';
  @override
  String get cleanerAppsFilterCleanable => 'Temizlenebilir';
  @override
  String get cleanerAppsSortLabel => 'Sırala';
  @override
  String get cleanerAppsSortSize => 'Önce en büyük';
  @override
  String get cleanerAppsSortName => 'Ad';
  @override
  String get cleanerAppsSortLastOpened => 'En eski etkinlik';
  @override
  String get cleanerAppsLargeThresholdLabel => 'Büyük uygulama';
  @override
  String get cleanerAppsStaleThresholdLabel => 'Görülmedi';
  @override
  String cleanerAppsDays(int days) => '$days gün';
  @override
  String get cleanerAppsSummaryFootprint => 'Doğrulanmış kaplanan alan';
  @override
  String get cleanerAppsSummaryAttention => 'İncelemeye değer';
  @override
  String get cleanerAppsSummaryLarge => 'Büyük uygulamalar';
  @override
  String get cleanerAppsSummaryStale => 'Yakın zamanda görülmeyenler';
  @override
  String get cleanerAppsSummaryCleanable => 'Temizlenebilir önbellek';
  @override
  String cleanerAppsThresholdAtLeast(String size) => '$size veya daha büyük';
  @override
  String cleanerAppsNotSeenForDays(int days) =>
      '$days gündür kayıtlı başlatma yok';
  @override
  String get cleanerAppsReviewableCache => 'Güvenli incelemeye uygun';
  @override
  String cleanerAppsShowingCount(int count) => '$count uygulama gösteriliyor';
  @override
  String get cleanerAppsNoResults => 'Bu filtrelerle eşleşen uygulama yok.';
  @override
  String get cleanerAppsUnknown => 'Bilinmiyor';
  @override
  String cleanerAppsLastOpened(String date) => 'Son görülme: $date';
  @override
  String cleanerAppsNotOpenedForDays(int days) => '$days gündür açılmadı';
  @override
  String get cleanerAppsUsageUnknownCompact =>
      'Yakın zamanda etkinlik verisi yok';
  @override
  String get cleanerAppsAttentionBadge => 'İncele';
  @override
  String get cleanerAppsViewOptions => 'Görünüm seçenekleri';
  @override
  String cleanerAppsUsageEvidence(String source, String confidence) =>
      '$source • $confidence';
  @override
  String cleanerAppsPossibleSize(String size) => 'Olası: $size';
  @override
  String cleanerAppsCleanableAmount(String size) => 'Temizlenebilir: $size';
  @override
  String get cleanerAppsDetails => 'Uygulama ayrıntıları';
  @override
  String get cleanerAppsUsageEvidenceLabel => 'Kullanım kanıtı';
  @override
  String get cleanerAppsSelectApp =>
      'Depolama durumunu görmek için bir uygulama seçin.';
  @override
  String get cleanerAppsConfirmedFootprint => 'Doğrulanmış';
  @override
  String get cleanerAppsPossibleFootprint => 'Olası';
  @override
  String get cleanerAppsStorageBreakdown => 'Depolama dökümü';
  @override
  String get cleanerAppsNoStorageDetails =>
      'Bu uygulama için ölçülmüş depolama konumu yok.';
  @override
  String get cleanerAppsSharedFolders =>
      'Paylaşılan / atanmamış büyük klasörler';
  @override
  String get cleanerAppsSharedFoldersDescription =>
      'Bu klasörler tek bir uygulamaya atanmamıştır ve temizlik için asla seçilmez.';
  @override
  String get cleanerAppsOpenFolder => 'Klasörü aç';
  @override
  String get cleanerAppsViewFiles => 'Dosyaları görüntüle';
  @override
  String get cleanerAppsFilesDescription =>
      'Bu uygulamayla ilişkili konumlardaki dosyaları inceleyin. Uygulama verileri ayarları ve kişisel dosyaları içerebilir.';
  @override
  String get cleanerAppsCleanableFilesHint =>
      'Bu konum bir temizlik kuralıyla eşleşiyor. İnceleme, konumun tamamı için temizlik önizlemesini açar.';
  @override
  String get cleanerAppsDataFilesHint =>
      'Bu dosyalar temizlenebilir çöp olarak tanımlanmamıştır. Elle yönetmek için klasörü açın.';
  @override
  String cleanerAppsFilesLoadFailed(String error) =>
      'Bu klasör okunamadı: $error';
  @override
  String get cleanerAppsManageInWindows => 'Windows\'ta yönet';
  @override
  String get cleanerAppsReviewCleanable => 'Temizlenebilir verileri incele';
  @override
  String get cleanerAppsAskAgent => 'CB Agent\'a sor';
  @override
  String cleanerAppsVersion(String version) => 'Sürüm $version';
  @override
  String cleanerAppsInstalledOrUpdated(String date) =>
      'Yüklendi veya güncellendi: $date';
  @override
  String get cleanerAppsSourceWin32 => 'Win32 uygulaması';
  @override
  String get cleanerAppsSourceStore => 'Microsoft Store uygulaması';
  @override
  String get cleanerAppsMeasurementMeasured => 'Ölçüldü';
  @override
  String get cleanerAppsMeasurementEstimated => 'Windows tahmini';
  @override
  String get cleanerAppsMeasurementPartial => 'Kısmi';
  @override
  String get cleanerAppsMeasurementUnknown => 'Bilinmeyen boyut';
  @override
  String get cleanerAppsAttributionConfirmed => 'Doğrulanmış';
  @override
  String get cleanerAppsAttributionPossible => 'Olası';
  @override
  String get cleanerAppsAttributionShared => 'Paylaşılan';
  @override
  String get cleanerAppsUsageUserAssist => 'Windows başlatma geçmişi';
  @override
  String get cleanerAppsUsagePrefetch => 'Windows Prefetch';
  @override
  String get cleanerAppsConfidenceHigh => 'Yüksek güven';
  @override
  String get cleanerAppsConfidenceMedium => 'Orta güven';
  @override
  String get cleanerAppsStorageInstall => 'Kurulum';
  @override
  String get cleanerAppsStorageLocalData => 'Yerel uygulama verileri';
  @override
  String get cleanerAppsStorageRoamingData => 'Dolaşan uygulama verileri';
  @override
  String get cleanerAppsStoragePackageData => 'Paket verileri';
  @override
  String get cleanerAppsStorageProgramData => 'Paylaşılan program verileri';
  @override
  String get cleanerAppsStorageCache => 'Önbellek';
  @override
  String get cleanerAppsStorageLogs => 'Günlükler';
  @override
  String get cleanerAppsStorageShared => 'Paylaşılan depolama';
  @override
  String get cleanerAppsStorageUnknown => 'Diğer depolama';
  @override
  String get cleanerAppsCleanableBadge => 'Temizlenebilir';

  // Cleaner - leftover app data
  @override
  String get cleanerLeftoversTitle => 'Kalan uygulama verileri';
  @override
  String get cleanerLeftoversUtilityDescription =>
      'Kaldırılmış veya eski uygulamalardan kalan klasörleri bulun';
  @override
  String get cleanerLeftoversLoading =>
      'Yüklü uygulamalar ve uygulama veri klasörleri okunuyor...';
  @override
  String get cleanerLeftoversIntro =>
      'Bu klasörler yüklü hiçbir uygulamayla eşleşmiyor. Taşınabilir uygulamalar ve komut satırı araçları yüklü olarak görünmeyebilir; silmeden önce her klasörü kontrol edin.';
  @override
  String get cleanerLeftoversInventoryUnavailable =>
      'Yüklü uygulama listesi okunamadı, bu yüzden kalan veriler belirlenemiyor.';
  @override
  String get cleanerLeftoversPartialBanner =>
      'Uygulama listesi veya disk taraması eksik. Bazı klasörler hâlâ kullanılıyor olabilir.';
  @override
  String get cleanerLeftoversSearchHint => 'Klasör ara';
  @override
  String get cleanerLeftoversInactiveLabel => 'Şu süredir değişmedi';
  @override
  String get cleanerLeftoversInactiveAny => 'Herhangi bir zaman';
  @override
  String cleanerLeftoversInactiveDays(int days) => '$days+ gün';
  @override
  String cleanerLeftoversHiddenRecent(int count) =>
      'Yakın zamanda kullanılan $count klasör gizlendi';
  @override
  String get cleanerLeftoversEmpty => 'Kalan klasör bulunamadı.';
  @override
  String cleanerLeftoversReasonOlderVersion(String app) =>
      '$app uygulamasının eski sürümü';
  @override
  String cleanerLeftoversLastModified(String date) => 'Son değişiklik $date';
  @override
  String get cleanerLeftoversActivityUnknown => 'Son değişiklik bilinmiyor';
  @override
  String get cleanerLeftoversPartialSize => 'Kısmen ölçüldü';
  @override
  String get cleanerLeftoversLocationLocal => 'Local AppData';
  @override
  String get cleanerLeftoversLocationRoaming => 'Roaming AppData';
  @override
  String get cleanerLeftoversLocationLocalLow => 'LocalLow';
  @override
  String get cleanerLeftoversLocationProgramData => 'ProgramData';
  @override
  String get cleanerLeftoversLocationUserPrograms => 'Kullanıcı programları';
  @override
  String get cleanerLeftoversLocationProgramFiles => 'Program Files';
  @override
  String cleanerLeftoversScanProgress(int done, int total) =>
      '$total klasörden $done tanesi kontrol edildi';
  @override
  String get cleanerLeftoversConfirmWarning =>
      'Bu klasörler artık yüklü olmayan uygulamaların ayarlarını, kayıtlarını veya oturum bilgilerini içerebilir. Onları hâlâ kullanan uygulamalar sıfırdan başlar.';
  @override
  String get cleanerLeftoversScan => 'Kalıntıları bul';
  @override
  String get cleanerLeftoversMeasuring => 'Kalan klasörler ölçülüyor...';
  @override
  String cleanerLeftoversReclaimable(String size) =>
      'En fazla $size boşaltılabilir';
  @override
  String cleanerLeftoversFound(String size) => 'Şimdiye kadar $size bulundu';
  @override
  String cleanerLeftoversSelected(String size, int count) =>
      '$size seçildi ($count klasör)';
  @override
  String get cleanerLeftoversTierNoApp => 'Artık yüklü olmayan uygulamalar';
  @override
  String get cleanerLeftoversTierNoAppHint =>
      'Bu klasörlerle eşleşen yüklü bir uygulama veya yayıncı yok.';
  @override
  String get cleanerLeftoversTierOlder => 'Eski sürümler';
  @override
  String get cleanerLeftoversTierOlderHint =>
      'Aynı uygulamanın daha yeni bir sürümü yüklü.';
  @override
  String cleanerLeftoversFolderCount(int count) => '$count klasör';
  @override
  String cleanerLeftoversMoveTo(int count, String size, String destination) =>
      '$count klasörü $destination konumuna taşı ($size)';
  @override
  String cleanerLeftoversConfirmTitle(String destination) =>
      '$destination konumuna taşınsın mı?';
  @override
  String cleanerLeftoversConfirmBody(
    int count,
    String size,
    String destination,
  ) =>
      '$count klasör ($size) $destination konumuna taşınacak. Oradan geri yükleyebilirsiniz.';
  @override
  String cleanerLeftoversCleaned(String size, String destination) =>
      '$size $destination konumuna taşındı. Boşaltana kadar yer kaplamaya devam eder.';
  @override
  String get cleanerLeftoversSelectAll => 'Tümünü seç';
  @override
  String get cleanerLeftoversColumnFolder => 'Klasör';
  @override
  String get cleanerLeftoversColumnChanged => 'Son değişiklik';
  @override
  String get cleanerLeftoversColumnSize => 'Boyut';
  @override
  String cleanerLeftoversDaysAgo(int days) => '$days gün önce';
  @override
  String cleanerLeftoversNewestFile(String path) =>
      'İçindeki en yeni dosya: $path';
  @override
  String get cleanerLeftoversChangedInFolder =>
      'Klasörün kendisinde değişiklik oldu, örneğin bir dosya silindi veya yeniden adlandırıldı';

  @override
  String get aiThinking0 => 'Düşünüyor...';
  @override
  String get aiThinking1 => 'Analiz ediyor...';
  @override
  String get aiThinking2 => 'Arıyor...';
  @override
  String get aiThinking3 => 'Yanıt oluşturuyor...';
  @override
  String get aiWaitingApproval => 'Onayınız bekleniyor...';
  @override
  String aiRunningTool(String toolName) => '$toolName çalıştırılıyor...';

  // Local AI Advisor
  @override
  String get localAiAdvisor => 'Yerel yapay zeka danışmanı';
  @override
  String get localAiAdvisorDescription =>
      'Kendi Gemma 4 modelinizle cihaz üzerinde temizlik önerileri';
  @override
  String get huggingFaceToken => 'Hugging Face belirteci';
  @override
  String get huggingFaceTokenHint =>
      'İsteğe bağlı: Özel modeller veya genişletilmiş katalog erişimi için';
  @override
  String get pasteToken => 'Belirteci yapıştır';
  @override
  String get tokenSaved => 'Belirteç güvenli şekilde kaydedildi';
  @override
  String get clearToken => 'Belirteci temizle';
  @override
  String get browseModels => 'Modellere göz at';
  @override
  String get installedModels => 'Yüklü modeller';
  @override
  String get noModelsInstalled => 'Henüz yüklü model yok';
  @override
  String get installModel => 'Yükle';
  @override
  String get uninstallModel => 'Kaldır';
  @override
  String get selectActiveModel => 'Etkin yap';
  @override
  String get modelInstalling => 'Model yükleniyor...';
  @override
  String get modelInstalled => 'Model başarıyla yüklendi';
  @override
  String get modelUninstalled => 'Model kaldırıldı';
  @override
  String get downloadProgress => 'İndirme ilerlemesi';
  @override
  String get noTokenSet => 'Belirteç ayarlanmadı';
  @override
  String get setTokenFirst => 'Önce Hugging Face belirtecinizi ayarlayın';
  @override
  String get openLocation => 'Konumu aç';
  @override
  String get localAiIncompatibleArtifact =>
      'Bu model dosyası cihaz üzerinde sohbetle uyumlu değil. Yerel sohbeti etkinleştirmek için LiteRT-LM sürümünü yeniden yükleyin.';
  @override
  String get localAiReinstallCompatible => 'Uyumlu modeli yeniden yükle';
  @override
  String get localAiContextWindow => 'Bağlam penceresi';
  @override
  String get localAiContextWindowHint =>
      'Sohbet başına en fazla belirteç (istem + yanıt). Yüksek değerler daha büyük dosyaları ve daha uzun sohbetleri işler ancak daha fazla bellek kullanır.';
  @override
  String get localAiTokensSuffix => 'belirteç';
  @override
  String get localAiInvalidTokenCount => 'Lütfen geçerli bir sayı girin';
  @override
  String get localAiModelStorage => 'Model depolama konumu';
  @override
  String get localAiModelStorageHint =>
      'İndirilen modeller bu klasöre kaydedilir. Değiştirildiğinde yüklü modeller oraya taşınır.';
  @override
  String get localAiModelStorageReset => 'Varsayılan konumu kullan';
  @override
  String get localAiModelStorageNotWritable =>
      'Modeller bu klasöre kaydedilemiyor';
  @override
  String get localAiMovingModels => 'Modeller taşınıyor';
  @override
  String get localAiModelsMoved => 'Modeller taşındı';
  @override
  String get localAiMoveModelsFailed => 'Modeller taşınamadı';
  @override
  String get aiReasoning => 'Düşünme';

  @override
  String get sshLocalConfig => '~/.ssh/config dosyasından';
  @override
  String get sshLocalConfigHint =>
      'Bağlantı ayrıntılarını doldurmak için yerel bir ana bilgisayar seçin.';
  @override
  String get sshNoLocalConfig =>
      '~/.ssh/config içinde ana bilgisayar bulunamadı. Aşağıya bir ana bilgisayar girin.';
  @override
  String get sshLocalKeys => 'Bu bilgisayardaki anahtarlar';
  @override
  String get sshLocalKeysHint =>
      '~/.ssh içinde algılandı. Güvenli kasaya aktarmak için bir anahtar seçin.';
  @override
  String get sshChooseKeyFile => 'Anahtar dosyasını seç';
  @override
  String get sshPasteKey => 'Özel anahtarı yapıştır';
  @override
  String get sshPassphraseHint =>
      'Yalnızca özel anahtar şifrelenmişse gereklidir.';
  @override
  String get sshImportHint =>
      'Yerel bir dosya kullanın veya OpenSSH / PEM özel anahtarını yapıştırın.';
  @override
  String get sshGenerateHint =>
      'Bir Ed25519 anahtarı oluşturun. Kaydettikten sonra genel anahtarını sunucunuza kopyalayın.';
  @override
  String get sshKeyImportFailed =>
      'Anahtar kaydedilemedi. Dosyayı, biçimi ve parolayı kontrol edip yeniden deneyin.';
  @override
  String get sshConnectionDetails => 'Bağlantı ayrıntıları';
  @override
  String get sshLocalKeyPending =>
      'Bu yerel anahtar, kaydettiğinizde veya bağlandığınızda içe aktarılacak.';
  @override
  String get sshConfigUnsupported =>
      'Bu ana bilgisayar burada desteklenmeyen bir proxy veya SSH sertifikası kullanıyor. Bağlanmadan önce ayarlarını kontrol edin.';
  @override
  String get sshDiscoveryIncomplete =>
      'Bazı yerel SSH ayarları yüklenemedi (okunamayan dosyalar veya koşullu Match kuralları). Doldurulan ayrıntıları kontrol edin.';

  // App updates
  @override
  String get checkForUpdates => 'Güncellemeleri denetle';
  @override
  String get updateChecking => 'Güncellemeler denetleniyor…';
  @override
  String get updateUpToDate => 'En son sürümü kullanıyorsunuz';
  @override
  String get updateAvailableTitle => 'Güncelleme mevcut';
  @override
  String get updateAvailableGeneric => 'Yeni bir sürüm mevcut';
  @override
  String get updateDownload => 'İndir';
  @override
  String get updateDownloading => 'Güncelleme indiriliyor…';
  @override
  String get updateStoreDownloading => 'Mağaza güncellemeyi indiriyor…';
  @override
  String get updateReadyTitle => 'Güncelleme yüklemeye hazır';
  @override
  String get updateReadyMessage =>
      'Uygulama, güncellemeyi yüklemek için kapanacak ve ardından yeniden açılacak. Devam etmeden önce çalışmanızı kaydedin.';
  @override
  String get updateAdminHint => 'Windows yönetici izni isteyecek.';
  @override
  String get updateInstallNow => 'Yükle ve yeniden başlat';
  @override
  String get updateLater => 'Daha sonra';
  @override
  String get updateInstalling => 'Güncelleme yükleniyor…';
  @override
  String get updateFailed => 'Güncelleme başarısız';
  @override
  String get updateRetry => 'Tekrar dene';
  @override
  String get updateReleaseNotes => 'Yenilikler';
  @override
  String get updateAction => 'Güncelle';
  @override
  String updateAvailableVersion(String version) => '$version sürümü mevcut';
  @override
  String updateCurrentVersion(String version) => 'Geçerli sürüm: $version';
  @override
  String get updateStatusSection => 'Uygulama güncellemesi';
  @override
  String get updateSectionFeatures => 'Yeni özellikler';
  @override
  String get updateSectionFixes => 'Düzeltmeler';
  @override
  String get updateSectionImprovements => 'İyileştirmeler';
  @override
  String get updateMinorChanges =>
      'Küçük düzeltmeler ve kararlılık iyileştirmeleri.';
  @override
  String get updateBackgroundHint =>
      'Güncelleme arka planda indirilir. Bu pencereyi kapatıp bildirim zilinden takip edebilirsiniz.';

  // Hardcoded-string cleanup
  @override
  String get chooseLocation => 'Konum seç';
  @override
  String get navigationHistoryLabel => 'Gezinme geçmişi';
  @override
  String get selectCommonTagsToRemove => 'Kaldırılacak ortak etiketleri seçin:';
  @override
  String get streamCreateFailed =>
      'Bu dosya akışa alınamadı. Ağ bağlantınızı kontrol edip yeniden deneyin.';
  @override
  String errorOpeningVideo(String error) => 'Video açılırken hata: $error';
  @override
  String unexpectedFileOpenError(String error) =>
      'Dosya açılırken beklenmeyen hata: $error';
  @override
  String get enterPath => 'Yolu girin...';
  @override
  String get clearCompleted => 'Tamamlananları temizle';
  @override
  String get running => 'Çalışıyor';
  @override
  String get notifications => 'Bildirimler';
  @override
  String get dismiss => 'Kapat';
  @override
  String get openFileLocation => 'Dosya konumunu aç';
  @override
  String get minimize => 'Simge durumuna küçült';
  @override
  String get maximize => 'Ekranı kapla';
  @override
  String get tabInactiveTooltip =>
      'Etkin değil (60 dakika sonra otomatik askıya alındı)';
  @override
  String get closeSplitView => 'Bölünmüş görünümü kapat';
  @override
  String get nothingToShow => 'Gösterilecek bir şey yok';
  @override
  String get albumNotFound => 'Albüm bulunamadı';
  @override
  String get invalidAlbumId => 'Geçersiz albüm kimliği';
  @override
  String get videoLibraryNotFound => 'Video kütüphanesi bulunamadı';
  @override
  String get invalidVideoLibraryId => 'Geçersiz video kütüphanesi kimliği';
  @override
  String get vpAdvancedControls => 'Gelişmiş denetimler';
  @override
  String get vpAudioTracks => 'Ses parçaları';
  @override
  String get vpAudioTracksStub => 'Ses parçası seçimi burada uygulanacak.';
  @override
  String get vpSubtitles => 'Altyazılar';
  @override
  String get vpPlaybackSpeed => 'Oynatma hızı';
  @override
  String vpPlaybackSpeedValue(String speed) => 'Oynatma hızı (${speed}x)';
  @override
  String get vpPictureInPicture => 'Resim içinde resim';
  @override
  String get vpExitPip => 'PiP\'den çık';
  @override
  String get vpVideoFilters => 'Video filtreleri';
  @override
  String get vpSleepTimer => 'Uyku zamanlayıcısı';
  @override
  String get vpSleepTimerActive => 'Uyku zamanlayıcısı (Etkin)';
  @override
  String get vpVideoSettings => 'Video ayarları';
  @override
  String get vpReset => 'Sıfırla';
  @override
  String get vpResetToDefault => 'Varsayılana sıfırla';
  @override
  String get vpOff => 'Kapalı';
  @override
  String vpHoursOption(int hours) => '$hours saat';
  @override
  String vpMinutesOption(int minutes) => '$minutes dakika';
  @override
  String get vpBrightness => 'Parlaklık';
  @override
  String get vpContrast => 'Karşıtlık';
  @override
  String get vpSaturation => 'Doygunluk';
  @override
  String get vpStreamSpeed => 'Akış hızı';
  @override
  String get vpBufferInfo => 'Arabellek bilgisi';
  @override
  String get vpRewind10 => '10 sn geri sar';
  @override
  String get vpForward10 => '10 sn ileri sar';
  @override
  String get vpCodec => 'Codec:';
  @override
  String get vpAuto => 'Otomatik';
  @override
  String get vpScaleMode => 'Video ölçekleme modu:';
  @override
  String get vpScaleContain => 'Pencereye sığdır (oranı koru, kırpma yok)';
  @override
  String get vpScaleCover => 'Kapla (doldur ve kırp)';
  @override
  String get vpScaleFill => 'Doldur (uzat)';
  @override
  String get vpScaleFitWidth => 'Genişliğe sığdır';
  @override
  String get vpScaleFitHeight => 'Yüksekliğe sığdır';
  @override
  String get vpScaleNone => 'Yok (özgün boyut)';
  @override
  String get vpScaleDown => 'Küçült';
  @override
  String get vpAudioDecoder => 'Ses kod çözücü:';
  @override
  String get vpSoftware => 'Yazılım';
  @override
  String get vpHardware => 'Donanım';
  @override
  String vpBufferSize(int mb) => 'Arabellek boyutu: ${mb}MB';
  @override
  String vpNetworkTimeout(int seconds) => 'Ağ zaman aşımı: ${seconds}sn';
  @override
  String get vpSubtitleEncoding => 'Altyazı kodlaması:';
  @override
  String get vpOutputFormat => 'Video çıkış biçimi:';
  @override
  String get remove => 'Kaldır';
  @override
  String get cancelSelection => 'Seçimi iptal et';
  @override
  String get deselectAll => 'Tüm seçimi kaldır';
  @override
  String albumRemoveImagesTitle(int count) => '$count görsel kaldırılsın mı?';
  @override
  String get albumRemoveImagesBody =>
      'Seçilen görseller bu albümden kaldırılsın mı? Özgün dosyalar silinmeyecek.';
  @override
  String get albumNever => 'Hiç';
  @override
  String albumSmartStatus(int rules, int sources, String last) =>
      '$rules kural • $sources kaynak • Son: $last';
  @override
  String get albumScanningFiles => 'Dosyalar taranıyor...';
  @override
  String albumAddingFiles(int current, int total) =>
      'Dosyalar ekleniyor... ($current/$total)';
  @override
  String get albumCompleted => 'Tamamlandı!';
  @override
  String get albumScanning => 'Taranıyor...';
  @override
  String get albumNoScanLocations => 'Yapılandırılmış tarama konumu yok';
  @override
  String albumScanningFound(int count) => 'Taranıyor... $count bulundu';
  @override
  String albumCompletedFound(int count) => 'Tamamlandı! $count dosya bulundu';
  @override
  String get albumCanceled => 'İptal edildi';
  @override
  String get albumScanLocations => 'Tarama konumları';
  @override
  String get albumNoLocationsSelected =>
      'Konum seçilmedi. Bu albüm için taranacak klasörler ekleyin.';
  @override
  String get albumAddFolder => 'Klasör ekle';
  @override
  String get albumEditAlbum => 'Albümü düzenle';
  @override
  String get albumManageRules => 'Kuralları yönet';
  @override
  String get albumShuffle => 'Karıştır';
  @override
  String get albumUnshuffle => 'Karıştırmayı kaldır';
  @override
  String get albumAddImagesTooltip => 'Görsel ekle';
  @override
  String get albumRemoveFromAlbum => 'Albümden kaldır';
  @override
  String get albumMoveSelectedToTrash =>
      'Seçilen dosyaları Çöp Kutusu\'na taşı';
  @override
  String albumSearchImagesIn(String name) => '$name içinde görsel ara';
  @override
  String get albumSmartLabel => 'Akıllı albüm (kurallara göre dinamik)';
  @override
  String get albumSources => 'Kaynaklar';
  @override
  String get albumRescan => 'Yeniden tara';
  @override
  String get albumRules => 'Kurallar';
  @override
  String get albumNoImages => 'Bu albümde görsel yok';
  @override
  String get albumNoImagesMatch => 'Aramanızla eşleşen görsel yok';
  @override
  String get albumAddImagesHint =>
      'Albümünüzü oluşturmaya başlamak için görsel ekleyin';
  @override
  String get albumAddImages => 'Görsel ekle';
  @override
  String albumDeleteOneConfirm(String name) =>
      '"$name" albümünü silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  @override
  String albumDeleteManyConfirm(int count) =>
      '$count albümü silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  @override
  String get albumDeletedOne => 'Albüm başarıyla silindi';
  @override
  String albumDeletedMany(int count) => '$count albüm başarıyla silindi';
  @override
  String albumDeleteFailedCount(int count) => '$count albüm silinemedi';
  @override
  String albumImageCount(int count) => '$count görsel';
  @override
  String get albumColumnPrivacy => 'Gizlilik';
  @override
  String get albumPublic => 'Herkese açık';
  @override
  String albumSourceCount(int count) => '$count kaynak';
  @override
  String get albumSourceSettings => 'Kaynak ayarları';
  @override
  String get albumEditAlbumLower => 'Albümü düzenle';
  @override
  String get albumSetCover => 'Kapak ayarla…';
  @override
  String get albumRandomCover => 'Rastgele kapak';
  @override
  String get albumOptions => 'Albüm seçenekleri';
  @override
  String get albumSearchSources => 'Görsel kaynaklarında ara';
  @override
  String get albumSearchAlbums => 'Albümlerde ara';
  @override
  String get albumNoMatchingResults => 'Eşleşen sonuç yok';
  @override
  String get albumNoSourcesYet => 'Henüz görsel kaynağı yok';
  @override
  String get albumNoAlbumsYet => 'Henüz albüm yok';
  @override
  String get albumAddSourceHint =>
      'Klasörlerindeki görsellere göz atmak için bir kaynak ekleyin';
  @override
  String get albumCreateFirstHint =>
      'Görsellerinizi düzenlemek için ilk albümünüzü oluşturun';
  @override
  String get albumCreateImageSource => 'Görsel kaynağı oluştur';
  @override
  String get albumCreateAlbum => 'Albüm oluştur';
  @override
  String get albumBadgeSource => 'Kaynak';
  @override
  String get albumNoImagesForCover => 'Kapak olarak seçilecek görsel yok';
  @override
  String get albumChooseCover => 'Kapak görseli seç';
  @override
  String get ruleDeleteTitle => 'Kuralı sil';
  @override
  String ruleDeleteConfirm(String name) =>
      '"$name" kuralını silmek istediğinizden emin misiniz?';
  @override
  String get ruleCreateNew => 'Yeni kural oluştur';
  @override
  String get ruleEmptyTitle => 'Otomatik albüm kuralları';
  @override
  String get ruleEmptyBody =>
      'Dosya adı desenleriyle eşleşen kurallar oluşturarak\nfotoğraflarınızı otomatik düzenleyin';
  @override
  String get ruleCreateFirst => 'İlk kuralınızı oluşturun';
  @override
  String get ruleExScreenshots => 'Ekran görüntüleri';
  @override
  String get ruleExScreenshotsDesc =>
      '"screenshot" içeren dosyalar → Ekran görüntüleri albümü';
  @override
  String get ruleExCamera => 'Kamera fotoğrafları';
  @override
  String get ruleExCameraDesc => '"IMG_" ile başlayan dosyalar → Kamera albümü';
  @override
  String get ruleExEdited => 'Düzenlenmiş fotoğraflar';
  @override
  String get ruleExEditedDesc =>
      '"_edited" ile biten dosyalar → Düzenlenenler albümü';
  @override
  String get rulePopularExamples => 'Popüler kural örnekleri';
  @override
  String ruleAlbumLabel(String name) => 'Albüm: $name';
  @override
  String ruleConditionLabel(String name) => 'Koşul: $name';
  @override
  String rulePatternLabel(String pattern) => 'Desen: "$pattern"';
  @override
  String get ruleMatches => 'Eşleşmeler';
  @override
  String get ruleLastTriggered => 'Son tetiklenme';
  @override
  String ruleDaysAgo(int n) => '$n gün önce';
  @override
  String ruleHoursAgo(int n) => '$n sa. önce';
  @override
  String ruleMinutesAgo(int n) => '$n dk. önce';
  @override
  String get ruleJustNow => 'Az önce';
  @override
  String get ruleCreateAutoRule => 'Otomatik kural oluştur';
  @override
  String get ruleCreate => 'Kural oluştur';
  @override
  String get ruleQuickTemplates => 'Hızlı şablonlar';
  @override
  String get ruleQuickTemplatesHint =>
      'Hızlıca başlamak için hazır bir şablon seçin';
  @override
  String get ruleExamples => 'Örnekler:';
  @override
  String get ruleCustom => 'Özel kural';
  @override
  String get ruleName => 'Kural adı';
  @override
  String get ruleNameHint =>
      'ör. Ekran görüntülerini Ekran görüntüleri albümüne';
  @override
  String get ruleTargetAlbum => 'Hedef albüm';
  @override
  String get ruleCondition => 'Koşul';
  @override
  String get rulePattern => 'Desen';
  @override
  String get rulePreview => 'Önizleme';
  @override
  String get rulePreviewHint =>
      'Kuralınızla hangi dosyaların eşleşeceğini görün';
  @override
  String get rulePreviewUpdatedHint =>
      'Güncellenen kuralınızla hangi dosyaların eşleşeceğini görün';
  @override
  String get ruleTestResults => 'Test sonuçları:';
  @override
  String get ruleCondContains => 'İçerir';
  @override
  String get ruleCondStartsWith => 'Şununla başlar';
  @override
  String get ruleCondEndsWith => 'Şununla biter';
  @override
  String get ruleCondEquals => 'Eşittir';
  @override
  String get ruleCondRegex => 'Regex deseni';
  @override
  String get ruleHintContains => 'ör. screenshot';
  @override
  String get ruleHintStartsWith => 'ör. IMG_';
  @override
  String get ruleHintEndsWith => 'ör. _edited';
  @override
  String get ruleHintEquals => 'ör. photo';
  @override
  String get ruleHintRegex => r'ör. ^IMG_\d{4}$';
  @override
  String get ruleEditAutoRule => 'Otomatik kuralı düzenle';
  @override
  String get ruleSaveChanges => 'Değişiklikleri kaydet';
  @override
  String get ruleDetails => 'Kural ayrıntıları';
  @override
  String errorWithDetail(String error) => 'Hata: $error';
  @override
  String get albumSelectingFiles => 'Dosyalar seçiliyor...';
  @override
  String get albumAddingSelectedFiles => 'Seçilen dosyalar ekleniyor...';
  @override
  String get albumAddTo => 'Albüme ekle';
  @override
  String get albumAddFromFolder => 'Klasörden ekle';
  @override
  String get albumAddFromFolderDesc => 'Seçilen klasördeki tüm görselleri ekle';
  @override
  String get albumAddSelectedPhotos => 'Seçilen fotoğrafları ekle';
  @override
  String get albumAddSelectedPhotosDesc =>
      'Eklenecek belirli görsel dosyalarını seçin';
  @override
  String get albumColorOptional => 'Albüm rengi (İsteğe bağlı)';
  @override
  String get albumEditTitle => 'Albümü düzenle';
  @override
  String get albumCreateTitle => 'Yeni albüm oluştur';
  @override
  String get albumNameRequiredLabel => 'Albüm adı *';
  @override
  String get albumNameHint => 'Albüm adını girin';
  @override
  String get albumNameRequired => 'Albüm adı gerekli';
  @override
  String get albumNameTooLong => 'Albüm adı en fazla 50 karakter olmalı';
  @override
  String get albumDescriptionLabel => 'Açıklama (İsteğe bağlı)';
  @override
  String get albumDescriptionHint => 'Albüm açıklamasını girin';
  @override
  String get albumDescriptionTooLong => 'Açıklama en fazla 200 karakter olmalı';
  @override
  String get albumDynamicSmart => 'Dinamik (akıllı) albüm';
  @override
  String get albumDynamicSmartDesc =>
      'İçerik Otomatik Kurallar ile belirlenir. Dosyalar açıkça saklanmaz.';
  @override
  String get albumAddingFilesToAlbum => 'Dosyalar albüme ekleniyor...';
  @override
  String get albumSearchAndSelect => 'Görselleri ara ve seç';
  @override
  String get albumSearchForImages => 'Görsel ara...';
  @override
  String albumSelectedOfTotal(int selected, int total) =>
      '$total içinden $selected seçildi';
  @override
  String get albumDeselectAllCaps => 'Tüm seçimi kaldır';
  @override
  String get albumLoadingImages => 'Görseller yükleniyor...';
  @override
  String get albumNoImagesFound => 'Görsel bulunamadı';
  @override
  String get albumTryDifferentSearch => 'Farklı bir arama terimi deneyin';
  @override
  String albumAddNImages(int count) => '$count görsel ekle';
  @override
  String get albumAddFolderToAlbum => 'Klasörü albüme ekle';
  @override
  String get albumAddAllFromFolder =>
      'Bu klasördeki tüm görseller albüme eklensin mi?';
  @override
  String albumFolderName(String name) => 'Klasör: $name';
  @override
  String get albumIncludeSubfolders => 'Alt klasörlerdeki görselleri dahil et';
  @override
  String get albumAddFolderButton => 'Klasör ekle';
  @override
  String get albumAddingFolder => 'Klasör albüme ekleniyor...';
  @override
  String albumImagesCountShort(int count) => '$count görsel';
  @override
  String get albumNoImagesShort => 'Görsel yok';
  @override
  String get albumCounting => 'Sayılıyor...';
  @override
  String get albumGoUp => 'Yukarı çık';
  @override
  String get albumSelectFolderTitle => 'Klasör seç';
  @override
  String get albumNoFoldersFound => 'Klasör bulunamadı';
  @override
  String albumCurrentFolder(String name) => 'Geçerli: $name';
  @override
  String get albumAddThisFolder => 'Bu klasörü ekle';
  @override
  String ivShareFailed(String error) => 'Görsel paylaşılamadı: $error';
  @override
  String get ivPrintSent => 'Görsel yazıcıya gönderildi';
  @override
  String get ivPrintFailed => 'Bu görsel için yazdırma başlatılamadı';
  @override
  String get ivDisplayFailed => 'Görsel görüntülenemedi';
  @override
  String get ivNoImages => 'Görüntülenecek görsel yok';
  @override
  String get previous => 'Önceki';
  @override
  String get next => 'Sonraki';
  @override
  String get ivInfo => 'Bilgi (I)';
  @override
  String get ivMore => 'Daha fazla';
  @override
  String get ivZoomOut => 'Uzaklaştır';
  @override
  String get ivZoomIn => 'Yakınlaştır';
  @override
  String get ivRotateLeft => 'Sola döndür';
  @override
  String get ivRotateRight => 'Sağa döndür';
  @override
  String get ivEditImage => 'Görseli düzenle';
  @override
  String get ivPauseSlideshow => 'Slayt gösterisini duraklat';
  @override
  String get ivPlaySlideshow => 'Slayt gösterisini oynat';
  @override
  String get ivExitFullscreen => 'Tam ekrandan çık';
  @override
  String get ivFullscreen => 'Tam ekran';
  @override
  String get ivPrint => 'Yazdır (Ctrl+P)';
  @override
  String get ivResetZoom => 'Yakınlaştırmayı sıfırla (0)';
  @override
  String get ivCopyPath => 'Dosya yolunu kopyala';
  @override
  String get ivHideThumbnails => 'Küçük resimleri gizle';
  @override
  String get ivShowThumbnails => 'Küçük resimleri göster';
  @override
  String get edDiscardTitle => 'Değişiklikler silinsin mi?';
  @override
  String get edDiscardBody => 'Düzenlemeleriniz kaydedilmedi.';
  @override
  String get edDiscard => 'Sil';
  @override
  String get edSaveDialogTitle => 'Düzenlenmiş kopyayı kaydet';
  @override
  String get edSavedCopy => 'Düzenlenmiş kopya kaydedildi';
  @override
  String edSaveFailed(String error) => 'Görsel kaydedilemedi: $error';
  @override
  String edEraseFailed(String error) => 'Silinemedi: $error';
  @override
  String get edAddText => 'Metin ekle';
  @override
  String get edTypeSomething => 'Bir şey yazın';
  @override
  String get add => 'Ekle';
  @override
  String get edCloseEditor => 'Düzenleyiciyi kapat (Esc)';
  @override
  String get edTitle => 'Düzenle';
  @override
  String get edUndo => 'Geri al (Ctrl+Z)';
  @override
  String get edRedo => 'Yinele (Ctrl+Y)';
  @override
  String get edHoldToCompare => 'Karşılaştırmak için basılı tutun';
  @override
  String get edSaving => 'Kaydediliyor...';
  @override
  String get edSaveCopy => 'Kopyayı kaydet';
  @override
  String get edToolCrop => 'Kırp';
  @override
  String get edToolAdjust => 'Ayarla';
  @override
  String get edToolFilters => 'Filtreler';
  @override
  String get edToolMarkup => 'İşaretleme';
  @override
  String get edToolErase => 'Sil';
  @override
  String get edAspectRatio => 'En boy oranı';
  @override
  String get edAspectFree => 'Serbest';
  @override
  String get edAspectOriginal => 'Özgün';
  @override
  String get edRotateFlip => 'Döndür ve çevir';
  @override
  String get edFlipHorizontal => 'Yatay çevir';
  @override
  String get edFlipVertical => 'Dikey çevir';
  @override
  String get edLightColour => 'Işık ve renk';
  @override
  String get edExposure => 'Pozlama';
  @override
  String get edWarmth => 'Sıcaklık';
  @override
  String get edTint => 'Ton';
  @override
  String get edVignette => 'Vinyet';
  @override
  String get edStrength => 'Yoğunluk';
  @override
  String get edFilterVivid => 'Canlı';
  @override
  String get edFilterWarm => 'Sıcak';
  @override
  String get edFilterCool => 'Soğuk';
  @override
  String get edFilterFade => 'Solgun';
  @override
  String get edFilterDramatic => 'Dramatik';
  @override
  String get edFilterMono => 'Tek renk';
  @override
  String get edFilterNoir => 'Kara film';
  @override
  String get edFilterSepia => 'Sepya';
  @override
  String get edTool => 'Araç';
  @override
  String get edPen => 'Kalem';
  @override
  String get edHighlighter => 'Vurgulayıcı';
  @override
  String get edArrow => 'Ok';
  @override
  String get edLine => 'Çizgi';
  @override
  String get edRectangle => 'Dikdörtgen';
  @override
  String get edEllipse => 'Elips';
  @override
  String get edText => 'Metin';
  @override
  String get edEraseMarkup => 'İşaretlemeyi sil';
  @override
  String get edColour => 'Renk';
  @override
  String get edTextSize => 'Metin boyutu';
  @override
  String get edSize => 'Boyut';
  @override
  String get edTextHint =>
      'Metnin gelmesini istediğiniz yere resmin üzerinde tıklayın.';
  @override
  String get edEraseTitle => 'Sil';
  @override
  String get edEraseHint =>
      'Kaldırmak istediğiniz yerin üzerini boyayın. Çevresinden doldurulur. Küçük nesnelerde ve lekelerde en iyi sonucu verir.';
  @override
  String get edBrush => 'Fırça';
  @override
  String edOpenFailed(String error) =>
      'Bu görsel düzenleme için açılamadı.\n$error';
  @override
  String get edErasing => 'Siliniyor...';
  @override
  String get edOriginal => 'Özgün';
  @override
  String get edDoubleClickReset => 'Sıfırlamak için çift tıklayın';
  @override
  String get cachePhotoThumbs => 'Fotoğraf küçük resimleri';
  @override
  String get cachePhotoThumbsDesc =>
      'Görsel ızgaraları ve görüntüleyiciler için oluşturulan JPEG önizlemeleri';
  @override
  String get cacheVideoThumbs => 'Video küçük resimleri';
  @override
  String get cacheVideoThumbsDesc =>
      'Videolar için önbelleğe alınmış kare önizlemeleri';
  @override
  String get cacheNetworkThumbs => 'Ağ küçük resimleri';
  @override
  String get cacheNetworkThumbsDesc =>
      'SMB / FTP / WebDAV küçük resim önbelleği';
  @override
  String get cacheLibrary => 'Video kütüphanesi önbelleği';
  @override
  String get cacheLibraryDesc =>
      'Video kütüphanesi meta verileri ve önbelleğe alınmış öğeler';
  @override
  String get cacheTempFiles => 'Geçici dosyalar';
  @override
  String get cacheTempFilesDesc => 'Geçici indirmeler ve çalışma dosyaları';
  @override
  String cacheLoadFailed(String error) =>
      'Önbellek bilgisi yüklenemedi: $error';
  @override
  String get cacheOpenFolderFailed => 'Klasör sistem gezgininde açılamadı';
  @override
  String cacheEntryCleared(String name) => '$name temizlendi';
  @override
  String cacheEntryClearFailed(String name, String error) =>
      '$name temizlenemedi: $error';
  @override
  String get cacheAllCleared => 'Tüm önbellek temizlendi';
  @override
  String cacheClearFailed(String error) => 'Önbellek temizlenemedi: $error';
  @override
  String get cacheTotalSize => 'Toplam boyut';
  @override
  String get cacheFilesLabel => 'Dosyalar';
  @override
  String get cacheBuckets => 'Gruplar';
  @override
  String cacheFilesCount(int count) => '$count dosya';
  @override
  String cachePercentOfTotal(String percent) =>
      'Toplam önbelleğin %$percent\'i';
  @override
  String dbLoadPrefsFailed(String error) =>
      'Veritabanı tercihleri yüklenirken hata: $error';
  @override
  String get dbClearAllWarning =>
      'Bu işlem tema, dil ve görünüm tercihleri dahil tüm uygulama ayarlarını siler. Uygulama yeniden başlayabilir.';
  @override
  String get dbNoPrefs => 'Kayıtlı tercih yok.';
  @override
  String dbRowsCount(int count) => '$count satır';
  @override
  String dbRangeOfTotal(int start, int end, int total) =>
      '$total içinden $start-$end';
  @override
  String get dbRowsPerPage => 'Sayfa başına satır';
  @override
  String dbPageOf(int page, int total) => 'Sayfa $page / $total';
  @override
  String get faNoData => 'Kullanılabilir veri yok';
  @override
  String get faShowInHub => 'Öne çıkan albümleri Galeri Merkezi\'nde göster';
  @override
  String get faAutoSelect => 'Son albümleri otomatik seç';
  @override
  String get faAutoSelectDesc =>
      'En son albümlerinizi otomatik olarak öne çıkar';
  @override
  String get faMax => 'En fazla öne çıkan albüm';
  @override
  String get faManual => 'Öne çıkan albümleri elle seç';
  @override
  String get laNoTokenInClipboard => 'Panoda belirteç bulunamadı';
  @override
  String get laRemoveModelConfirm => 'Bu model cihazınızdan kaldırılsın mı?';
  @override
  String laOpenLocationFailed(String error) => 'Konum açılamadı: $error';
  @override
  String get laRuntimePending => 'Çalışma zamanı bekleniyor';
  @override
  String get laRequiresGguf => 'GGUF gerekir';
  @override
  String get laInstallFailed => 'Yükleme başarısız';
  @override
  String get laDownloading => 'İndiriliyor...';
  @override
  String tagTabName(String tag) => 'Etiket: $tag';
  @override
  String tagThumbnailSet(String tag) => '"$tag" için küçük resim ayarlandı';
  @override
  String get tagThumbnailSetFailed => 'Küçük resim ayarlanamadı';
  @override
  String tagThumbnailRemoved(String tag) =>
      '"$tag" için küçük resim kaldırıldı';
  @override
  String get tagThumbnailRemoveFailed => 'Küçük resim kaldırılamadı';
  @override
  String tagHasChildren(int count, String children) =>
      'Bu etiketin $count alt etiketi var: $children';
  @override
  String get tagWhatToDo => 'Ne yapmak istersiniz?';
  @override
  String get tagDeleteParentOnly => 'Yalnızca üst etiketi sil';
  @override
  String get tagDeleteParentAndChildren => 'Üst ve alt etiketleri sil';
  @override
  String tagsDeletedList(int count, String tags) =>
      '$count etiket silindi: $tags';
  @override
  String tagCannotAddChild(String name) =>
      '"$name" eklenemiyor - döngüsel başvuru veya hata';
  @override
  String tagCannotSetParent(String name) =>
      '"$name" üst etiket olarak ayarlanamıyor - döngüsel başvuru veya hata';
  @override
  String tagHierarchyTitle(String tag) => 'Hiyerarşi: "$tag"';
  @override
  String get tagNoParents => 'Üst etiket yok';
  @override
  String get tagNoChildren => 'Alt etiket yok';
  @override
  String get tagAddParentHint => 'Üst etiket ekle...';
  @override
  String get tagAddChildHint => 'Alt etiket ekle... (virgülle ayırın)';
  @override
  String get tagQuickPicks => 'Hızlı seçimler';
  @override
  String get tagQuickPicksDesc =>
      'Popüler ve son kullanılan etiketlerden seçin';
  @override
  String get tagBrowseTreeDesc =>
      'Etiket ağacına göz atın — alt etiketleri seçmek için bir üst etiketi genişletin.';
  @override
  String get tagSearchTitle => 'Etikete göre ara';
  @override
  String get tagSearchInputLabel => 'Aramak için bir etiket girin';
  @override
  String get tagSearchInputHint => 'Örnek: önemli, iş, kişisel';
  @override
  String get tagSearchGlobal => 'Genel arama';
  @override
  String get tagSearchGlobalDesc => 'Cihazınızın herhangi bir yerinde arayın';
  @override
  String get tagSearchNoTags => 'Kullanılabilir etiket yok';
  @override
  String get newMenu => 'Yeni';
  @override
  String get customizeMenu => 'Özelleştir...';
  @override
  String get fileCreateFailedDetail =>
      'Dosya zaten var olabilir veya hedef yazılabilir değil';
  @override
  String get customizeNewMenuTitle => 'Yeni menüsünü özelleştir';
  @override
  String folderFilesFolders(int files, int folders) =>
      '$files dosya, $folders klasör';
  @override
  String dndMoved(int count) => '$count öğe taşındı';
  @override
  String get dndFolderIntoItself => 'Bir klasör kendi içine taşınamaz';
  @override
  String get dndLocalOnly => 'Sürükle bırak yalnızca yerel yolları destekler';
  @override
  String get dndDestinationMissing => 'Hedef klasör kullanılamıyor';
  @override
  String get dndMoveFailed => 'Taşıma başarısız';
  @override
  String get toggleView => 'Görünümü değiştir';
  @override
  String get folderNameLabelShort => 'Klasör adı';
  @override
  String get vfPickFrame => 'Videodan kare seç';
  @override
  String get vfExtractFailed => 'Kare çıkarılamadı. Farklı bir konum deneyin.';
  @override
  String get pause => 'Duraklat';
  @override
  String get play => 'Oynat';
  @override
  String vfPreviewAt(String time) => '$time konumunda önizleme';
  @override
  String get preview => 'Önizleme';
  @override
  String get vfUseFrame => 'Bu kareyi kullan';
  @override
  String get cfCsvSpreadsheet => 'CSV e-tablosu';
  @override
  String get cfNoTemplates => 'Kullanılabilir şablon yok';
  @override
  String cfNoResultsFor(String query) => '"$query" için sonuç yok';
  @override
  String cfExtension(String ext) => 'Uzantı: $ext';
  @override
  String cfCreatesFile(String ext) => '$ext dosyası oluşturur';
  @override
  String mpDriveSystem(String letter) => '$letter (Sistem)';
  @override
  String mpDriveOther(String letter) => '$letter (Sürücü)';
  @override
  String get tagManageHierarchy => 'Hiyerarşiyi yönet';
  @override
  String get tagFilterParent => 'Üst etiketler';
  @override
  String get tagFilterChild => 'Alt etiketler';
  @override
  String get tagFilterStandalone => 'Bağımsız';
  @override
  String get tagFilterHasThumb => 'Küçük resmi var';
  @override
  String get tagFilterNoThumb => 'Küçük resmi yok';
  @override
  String get tagFilterAll => 'Tümü';
  @override
  String get tagFilterTitle => 'Etiketleri filtrele';
  @override
  String get tagManageHierarchyTooltip => 'Hiyerarşiyi yönet (üst/alt)';
  @override
  String get tagDoubleClickChildren =>
      'Alt etiketleri açmak için çift tıklayın';
  @override
  String get tagDoubleClickFiles => 'Dosyaları açmak için çift tıklayın';
  @override
  String get tagHierarchyFormatHelp =>
      'Hiyerarşi için üst:alt biçimini kullanın\nör. Oyuncu:Ali veya Oyuncu:Ali,Veli';
  @override
  String get tagInvalidFormat =>
      'Geçersiz biçim. üst:alt veya üst:alt1,alt2 kullanın';
  @override
  String get tagNoChildSpecified => 'Alt etiket belirtilmedi';
  @override
  String tagRelationFailed(String parent, String child) =>
      'İlişki oluşturulamadı: $parent -> $child (döngüsel başvuru mu?)';
  @override
  String tagHierarchyCreated(String parent, String children, int count) =>
      'Hiyerarşi oluşturuldu: $parent -> $children ($count ilişki)';
  @override
  String get tagCircularHierarchy =>
      'Döngüsel etiket hiyerarşisi oluşturulamaz';
  @override
  String tagMovedUnder(String child, String parent) =>
      '"$child", "$parent" altına taşındı';
  @override
  String get aiViewRawPayload => 'Ham yükü görüntüle';
  @override
  String get aiViewPayload => 'Yükü görüntüle';
  @override
  String get aiProviderError => 'Sağlayıcı hatası';
  @override
  String get aiToolActivity => 'Araç etkinliği';
  @override
  String aiContextInfo(int messages, String chars) =>
      '$messages mesaj · $chars karakter\nBağlam kırpma ~24K karakterde başlar';
  @override
  String get aiAllDrives => 'Tüm sürücüler';
  @override
  String aiLocalContextFull(int tokens) =>
      'Yerel modelin bağlam penceresi ($tokens belirteç) doldu. Ayarlar > Yerel yapay zeka danışmanı bölümünden Bağlam penceresini artırın veya yeni bir sohbet başlatın.';
  @override
  String get aiContextWorkingIn => 'Çalışma klasörü';
  @override
  String get aiContextCleanerScan => 'Disk Temizleyici taraması';
  @override
  String get aiContextNetwork => 'Ağ klasörü';
  @override
  String get aiContextAppScreen => 'Uygulama ekranı';
  @override
  String aiContextDefaultFolder(String folder) => 'varsayılan klasör: $folder';
  @override
  String aiContextFolderHint(String path) =>
      'CB Agent bu klasörde ve alt klasörlerinde dosya arar, okur ve değiştirir; göreli yollar buradan başlar.\n$path';
  @override
  String aiContextDrivesHint(String path) =>
      'CB Agent tüm sürücüleri görebilir. Mesajınızda bir klasör belirtilmezse şurada çalışır:\n$path';
  @override
  String aiContextCleanerHint(String path) =>
      'CB Agent bu sekmede açık olan Disk Temizleyici taramasını okur. Diğer dosyalar için şurada çalışır:\n$path';
  @override
  String aiContextScreenHint(String path) =>
      'Bu ekran bir klasör değil, bu yüzden CB Agent şurada çalışır:\n$path\nBaşka bir yerde çalışması için mesajınızda bir klasör belirtin.';
  @override
  String aiContextNetworkHint(String path) =>
      'CB Agent ağ klasörlerini (SMB, FTP...) henüz okuyamıyor, bu yüzden şurada çalışır:\n$path';
  @override
  String get aiThinking => 'Düşünüyor...';
  @override
  String get aiDropToMention => 'Anmak için bırakın';
  @override
  String aiFilesAttached(int count) => '$count dosya eklendi';
  @override
  String get aiStopGeneration => 'Üretimi durdur';
  @override
  String aiLinkCopied(String href) => 'Bağlantı kopyalandı: $href';
  @override
  String get aiJustNow => 'Az önce';
  @override
  String aiMinutesAgo(int n) => '$n dk. önce';
  @override
  String aiHoursAgo(int n) => '$n sa. önce';
  @override
  String aiDaysAgo(int n) => '$n gün önce';
  @override
  String get aiFileNotFound => 'Dosya bulunamadı';
  @override
  String get aiOpenFolderTooltip => 'Klasörü aç';
  @override
  String get aiOpenFileTooltip => 'Dosyayı aç';
  @override
  String get aiNoPayload =>
      'Henüz yük yakalanmadı. İsteği görmek için önce bir mesaj gönderin.';
  @override
  String get aiRawApiPayload => 'Ham API yükü';
  @override
  String get aiCopiedToClipboard => 'Panoya kopyalandı';
  @override
  String get aiStreaming => 'akış';
  @override
  String get aiNonStreaming => 'akışsız';
  @override
  String get aiLoadingContent => 'İçerik yükleniyor...';
  @override
  String aiMoreLines(int count) => '... ($count satır daha)';
  @override
  String get aiToolOk => 'TAMAM';
  @override
  String get aiToolFailed => 'BAŞARISIZ';
  @override
  String foErrorCopying(String error) => 'Kopyalama hatası: $error';
  @override
  String foErrorCutting(String error) => 'Kesme hatası: $error';
  @override
  String foErrorPasting(String error) => 'Yapıştırma hatası: $error';
  @override
  String foErrorRenaming(String error) => 'Yeniden adlandırma hatası: $error';
  @override
  String get foNothingToPaste => 'Yapıştırılacak bir şey yok — pano boş';
  @override
  String foMovingOne(String name) => '"$name" taşınıyor';
  @override
  String foCopyingOne(String name) => '"$name" kopyalanıyor';
  @override
  String foMovingMany(int count) => '$count öğe taşınıyor';
  @override
  String foCopyingMany(int count) => '$count öğe kopyalanıyor';
  @override
  String foMoveProgress(int done, int total, String dest) =>
      '$total öğeden $done. öğe $dest konumuna taşınıyor';
  @override
  String foCopyProgress(int done, int total, String dest) =>
      '$total öğeden $done. öğe $dest konumuna kopyalanıyor';
  @override
  String foMovedItems(int count, String dest) =>
      '$count öğe $dest konumuna taşındı';
  @override
  String foCopiedItems(int count, String dest) =>
      '$count öğe $dest konumuna kopyalandı';
  @override
  String get foMovingVerb => 'Taşınıyor';
  @override
  String get foCopyingVerb => 'Kopyalanıyor';
  @override
  String foPasteDetailNoSource(String action, int count, String dest) =>
      '$action: $count öğe → $dest';
  @override
  String foPasteDetail(
    String action,
    String source,
    String from,
    String dest,
  ) => '$action: $source, $from konumundan $dest konumuna';
  @override
  String foAndMore(String name, int more) => '$name ve $more öğe daha';
  @override
  String foDeleteDetail(String action, String item, String parent) =>
      '$action: $item, $parent konumundan';
  @override
  String get foActionPermanentDelete => 'Kalıcı olarak sil';
  @override
  String get foActionMoveToTrash => 'Çöp Kutusu\'na taşı';
  @override
  String foDeletingOnePerm(String name) => '"$name" kalıcı olarak siliniyor';
  @override
  String foDeletingOneTrash(String name) => '"$name" Çöp Kutusu\'na taşınıyor';
  @override
  String foDeletingFilesPerm(int count) =>
      '$count dosya kalıcı olarak siliniyor';
  @override
  String foDeletingFilesTrash(int count) =>
      '$count dosya Çöp Kutusu\'na taşınıyor';
  @override
  String foDeletingItemsPerm(int count) => '$count öğe kalıcı olarak siliniyor';
  @override
  String foMovingOneTrash(String name) => '"$name" Çöp Kutusu\'na taşınıyor';
  @override
  String foMovingItemsTrash(int count) => '$count öğe Çöp Kutusu\'na taşınıyor';
  @override
  String foPermDeletedProgress(int done, int total) =>
      '$total öğeden $done tanesi kalıcı olarak silindi';
  @override
  String foTrashedProgress(int done, int total) =>
      '$total öğeden $done tanesi Çöp Kutusu\'na taşındı';
  @override
  String foPermDeletedFiles(int count) => '$count dosya kalıcı olarak silindi';
  @override
  String foTrashedFiles(int count) => '$count dosya Çöp Kutusu\'na taşındı';
  @override
  String foPermDeletedItems(int count) => '$count öğe kalıcı olarak silindi';
  @override
  String foTrashedItems(int count) => '$count öğe Çöp Kutusu\'na taşındı';
  @override
  String foAdminDeletingOne(String name) => '"$name" yönetici olarak siliniyor';
  @override
  String foAdminDeletingMany(int count) =>
      '$count öğe yönetici olarak siliniyor';
  @override
  String get foAdminWaiting => 'Windows yönetici onayı bekleniyor';
  @override
  String foAdminDeletedOne(String path) => '"$path" yönetici olarak silindi.';
  @override
  String foAdminDeletedMany(int count) => '$count öğe yönetici olarak silindi.';
  @override
  String foAdminFailedOne(String path) =>
      '"$path" için yönetici olarak silme iptal edildi veya başarısız oldu.';
  @override
  String foAdminFailedMany(int count) =>
      '$count öğe için yönetici olarak silme iptal edildi veya başarısız oldu.';
  @override
  String get foDeleteFailed => 'Silme başarısız';
  @override
  String foFirstFailureItems(int count, String path) =>
      '$count öğe; ilk hata: "$path"';
  @override
  String foCouldNotDeleteAccessDenied(String item) =>
      '$item silinemedi: Erişim reddedildi. Klasör izinlerini kontrol edin veya uygulamayı yönetici olarak çalıştırın.';
  @override
  String foCouldNotDeleteReason(String item, String reason) =>
      '$item silinemedi: $reason.';
  @override
  String foCouldNotDelete(String item) => '$item silinemedi.';
  @override
  String get fnDirNotExist => 'Dizin mevcut değil';
  @override
  String get fnStoragePermission => 'Depolama izni gerekli';
  @override
  String fnErrorSorting(String error) => 'Sıralama hatası: $error';
  @override
  String fnInvalidRegex(String error) => 'Geçersiz regex: $error';
  @override
  String get fnAccessDeniedAdmin =>
      'Erişim reddedildi. Yönetici olarak çalıştırmayı deneyin.';
  @override
  String tsErrorLoadingTags(String error) =>
      'Etiketler yüklenirken hata: $error';
  @override
  String tsErrorAddingTag(String error) => 'Etiket eklenirken hata: $error';
  @override
  String tsErrorRemovingTag(String error) =>
      'Etiket kaldırılırken hata: $error';
  @override
  String tsErrorBatchAdding(String error) =>
      'Toplu etiket eklenirken hata: $error';
  @override
  String tsTagSearchError(String error) => 'Etiket arama hatası: $error';
  @override
  String tsGlobalTagSearchError(String error) =>
      'Genel etiket arama hatası: $error';
  @override
  String tsMultiTagSearchError(String error) =>
      'Çoklu etiket arama hatası: $error';
  @override
  String tsGlobalMultiTagSearchError(String error) =>
      'Genel çoklu etiket arama hatası: $error';
  @override
  String get jlTemp => 'GEÇİCİ';
  @override
  String get jlBrowser => 'TARAYICI';
  @override
  String get jlRecycle => 'GERİ DÖN.';
  @override
  String get jlThumbs => 'KÜÇÜK RESİM';
  @override
  String get jlAppCache => 'UYG. ÖNBELLEĞİ';
  @override
  String get jlCrashLog => 'ÇÖKME/GÜNLÜK';
  @override
  String get jlWinUpdate => 'WIN GÜNCELLEME';
  @override
  String get jlPrefetch => 'ÖN YÜKLEME';
  @override
  String get jlDelivery => 'TESLİMAT';
  @override
  String get jlDevCache => 'GELİŞTİRİCİ ÖNB.';
  @override
  String get jlJunk => 'GEREKSİZ';
  @override
  String get treeLoadFailedRetry =>
      'Yüklenemedi. Yeniden denemek için dokunun.';
  @override
  String cleanerRefreshFailed(String error) => 'Yenileme başarısız: $error';
  @override
  String cleanerLoadPropsFailed(String error) =>
      'Özellikler yüklenemedi: $error';
  @override
  String get aiProviderNameHint => 'Benim OpenAI\'ım';
  @override
  String get aiSystemPromptHint => 'İsteğe bağlı özel sistem istemi...';
  @override
  String get vlNameHint => 'Filmlerim';
  @override
  String get vlDescriptionHint => 'Kişisel film koleksiyonu';

  @override
  String get cleanerReviewSectionsTitle => 'Temizlemeden önce inceleyin';
  @override
  String cleanerScanWarnings(int count) => 'Tarama uyarıları ($count)';
  @override
  String cleanerReviewTitle(String name) => '$name (yalnızca inceleme)';
  @override
  String cleanerReviewSummary(int count, String size) => '$count öğe · $size';
  @override
  String get cleanerDeveloperAnalysisTitle =>
      'Geliştirici analiz ve derleme önbellekleri';
  @override
  String get cleanerDeveloperAnalysisReason =>
      'En az 7 gündür değişmeyen Dart analiz, C/C++ önceden derlenmiş başlık ve Go derleme önbellekleri. Önce düzenleyicileri, dil sunucularını ve derlemeleri kapatın. Sonraki analiz veya derleme daha uzun sürebilir.';
  @override
  String get cleanerDeveloperDownloadsTitle =>
      'Geliştirici araçlarının indirmeleri';
  @override
  String get cleanerDeveloperDownloadsReason =>
      'En az 7 gündür değişmeyen geliştirici aracı indirme önbellekleri. Önce kurulumları, güncellemeleri ve derlemeleri tamamlayın. Sonraki kurulumlar internet gerektirebilir; yüklü eklentiler, ortamlar ve modeller korunur.';
  @override
  String get cleanerElectronCrashTitle => 'Electron çökme raporları';
  @override
  String get cleanerElectronCrashReason =>
      'En az 7 gündür değişmeyen Crashpad minidump dosyaları. Sorun giderme için gereken raporları saklayın ve önce ilgili uygulamaları kapatın.';
  @override
  String get cleanerCppDatabaseReason =>
      'C/C++ kod veritabanları. Yalnızca inceleme; yeniden oluşturmak zaman alabilir. Bu dosyalar temizlik için asla seçilmez.';
  @override
  String get cleanerVcpkgReason =>
      'vcpkg derleme dosyaları, indirmeler ve paketler. Yalnızca inceleme; mevcut derlemeler veya çevrimdışı kurulumlar için gerekli olabilir. Temizlik için asla seçilmez.';
  @override
  String get cleanerNvidiaReason =>
      'NVIDIA gölgelendirici önbellekleri. Yalnızca inceleme; yeniden oluşturmak takılmalara neden olabilir. Temizlik için asla seçilmez.';
  @override
  String get cleanerUnrealReason =>
      'Unreal Zen ve türetilmiş veri önbellekleri. Yalnızca inceleme; proje verilerini yeniden oluşturmak zaman alabilir. Temizlik için asla seçilmez.';
  @override
  String get cleanerPikPakReason =>
      'PikPak oynatıcı önbelleği. Yalnızca inceleme; oynatma için gerekli medya içerebilir. Temizlik için asla seçilmez.';
  @override
  String get cleanerInstallerReason =>
      'Visual Studio ve Windows kurulum paketleri. Yalnızca inceleme; yazılımı onarmak, güncellemek veya kaldırmak için gerekli olabilir. Temizlik için asla seçilmez.';
}
