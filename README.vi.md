# CB File Hub

[English](README.md) | [Tiếng Việt](README.vi.md)

<p align="center"><img src="cb_file_manager/assets/images/logo_circle.png" alt="Logo CB File Hub" width="160" /></p>

CB File Hub là ứng dụng quản lý tập tin đa nền tảng dành cho thư viện dữ liệu lớn. Ứng dụng kết hợp duyệt tập tin, tab, tag, album, quản lý và tải torrent, xem/chỉnh sửa đa phương tiện, truy cập mạng/SSH, sao lưu cài đặt và tag, dọn ổ đĩa cùng trợ lý AI trong một không gian làm việc.

- [Tải từ Microsoft Store](https://apps.microsoft.com/detail/9nchpzkc4m5c)
- [Tải từ Google Play](https://play.google.com/store/apps/details?id=com.cbv.filehub)
- [Các bản phát hành](https://github.com/coolbirdzik/cb-file-hub/releases/latest)
- [Website coolbird.net](https://coolbird.net)

## Tính năng nổi bật

- **Duyệt tập tin linh hoạt:** nhiều tab, chia đôi, ghim vị trí, khôi phục phiên và các chế độ xem quen thuộc.
- **Thư viện torrent:** index chung, nơi lưu tùy chọn, nhập từ ứng dụng khác, hợp nhất mục trùng và quản lý tải xuống.
- **Ảnh, video và âm thanh:** thư viện trực quan, hình thu nhỏ, trình xem, chỉnh sửa ảnh và trình phát tích hợp.
- **Tag và album:** tag cha/con, tìm theo nhiều tag, album thủ công và album thông minh theo quy tắc.
- **Tập tin mạng và SSH:** SMB, FTP, SFTP, WebDAV, hồ sơ SSH, khóa và terminal.
- **CB Agent:** tìm tập tin bằng ngôn ngữ tự nhiên, đề xuất tổ chức và hỗ trợ đánh giá trước khi dọn dẹp.
- **Dọn ổ đĩa Windows:** xem thư mục lớn, file tạm, bộ nhớ đệm và chọn chính xác mục cần xử lý.
- **Sao lưu và cá nhân hóa:** sao lưu cài đặt/tag, các tích hợp đám mây khả dụng, giao diện sáng/tối và màu nhấn.

## Hình ảnh

<table>
  <tr>
    <td width="50%"><img src="screenshots/promo/vi/desktop/01_duyet_tap_tin.png" alt="Duyệt tập tin CB File Hub" /><p>Duyệt tập tin với tab và hình thu nhỏ.</p></td>
    <td width="50%"><img src="screenshots/promo/vi/desktop/04_tim_kiem_ai.png" alt="CB Agent tìm tập tin" /><p>CB Agent hỗ trợ tìm kiếm cạnh trình duyệt tập tin.</p></td>
  </tr>
  <tr>
    <td width="50%"><img src="screenshots/auto/desktop/ssh_workspace.png" alt="Không gian làm việc SSH" /><p>Máy chủ, khóa và kết nối SSH.</p></td>
    <td width="50%"><img src="screenshots/promo/vi/desktop/10_don_dep_o_dia.png" alt="Dọn dẹp ổ đĩa Windows" /><p>Xem kết quả quét và đánh giá trước khi dọn dẹp.</p></td>
  </tr>
</table>

### Thư viện torrent và tải xuống

<table>
  <tr>
    <td width="50%"><img src="screenshots/features/torrents/vi/qbittorrent.png" alt="Nhập torrent từ qBittorrent và xác nhận dọn nguồn" /><p>Nhập qBittorrent và xem tùy chọn dọn file nguồn.</p></td>
    <td width="50%"><img src="screenshots/features/torrents/vi/client-import.png" alt="Nhập torrent từ hồ sơ Transmission hoặc thư mục tùy chỉnh" /><p>Nhập ứng dụng khác từ hồ sơ tìm được hoặc thư mục riêng.</p></td>
  </tr>
  <tr>
    <td width="50%"><img src="screenshots/features/torrents/vi/add-link.png" alt="Magnet trong clipboard được tự điền vào hộp thoại thêm liên kết" /><p>Tự điền magnet hợp lệ từ clipboard.</p></td>
    <td width="50%"><img src="screenshots/features/torrents/vi/download.png" alt="Chọn thư mục tải torrent và có bắt đầu tải ngay hay không" /><p>Chọn nơi lưu nội dung và có tải ngay hay không.</p></td>
  </tr>
</table>

Ảnh torrent được dựng từ các hộp thoại Flutter của ứng dụng với dữ liệu mẫu.

## Các chức năng

### Quản lý tập tin và không gian làm việc

- Duyệt dữ liệu cục bộ và vị trí mạng trong cùng giao diện.
- Mở nhiều tab, chia đôi khung xem, ghim thư mục/ổ đĩa và khôi phục phiên tab.
- Dùng chế độ danh sách, ô, lưới, chi tiết, cây và cột; các khung xem lớn tải mục theo nhu cầu.
- Tìm kiếm, dùng biểu thức chính quy, sắp xếp, chọn nhiều, kéo thả và phím tắt.
- Thực hiện các thao tác tạo, đổi tên, sao chép, di chuyển, xóa và xem thuộc tính.
- Theo dõi công việc đang chạy và cập nhật được hỗ trợ trong Trung tâm trạng thái.

### Torrent

- Lưu index chung trong khi file `.torrent` vẫn nằm ở nơi bạn chọn; hỗ trợ chế độ Chỉ index, Sao chép và Di chuyển.
- Duyệt thư viện lớn với tải theo nhu cầu, số file mỗi trang tùy chỉnh, các chế độ xem, tìm kiếm và sắp xếp.
- Nhấn F5 để quét nguồn, thêm torrent mới và bỏ qua nhanh file đã có.
- Thêm file `.torrent`, magnet hoặc URL torrent HTTP/HTTPS; tự điền magnet hợp lệ từ clipboard khi mở Thêm bằng liên kết.
- Chọn thư mục lưu nội dung tải xuống và có tải ngay hay không; ghi nhớ lựa chọn, tạm dừng, tiếp tục và dừng tác vụ.
- Trong cài đặt Torrent, có thể tắt hộp thoại tải để dùng thư mục và lựa chọn tải ngay đã lưu; nếu chưa có thư mục, ứng dụng hỏi để chọn lần đầu.
- Dùng lại tab Torrent khi mở magnet/file; các yêu cầu liên tiếp được xử lý lần lượt.
- Hỏi xác nhận khi trùng info hash; hợp nhất tracker và nguồn, giữ tác vụ cùng thư mục tải hiện tại.
- Nhập bản sao lưu qBittorrent, kể cả mục có thể khôi phục khi thiếu `.torrent` riêng. Tùy chọn dọn nguồn yêu cầu đóng qBittorrent và xác nhận; giữ nội dung đã tải.
- Nhập file `.torrent` đã lưu của µTorrent, BitTorrent, Transmission, Deluge hoặc thư mục portable/tùy chỉnh.
- Chuột phải để sao chép magnet cho một hoặc nhiều mục; xem tiến độ, tốc độ, seed, peer, tracker và các cột thông tin khác.
- Tải torrent trên máy tính dùng aria2, hỗ trợ BitTorrent v1/hybrid. Xem [hướng dẫn Torrent](docs/features/10-torrent-library.md) để biết chi tiết theo nền tảng.

### Ảnh, video và âm thanh

- Duyệt thư viện ảnh/video và hình thu nhỏ cho tập tin, thư mục, nội dung đa phương tiện.
- Chọn cách ảnh thu nhỏ vừa khung hoặc phủ khung; điều chỉnh vị trí lấy ảnh từ video.
- Xem ảnh và chỉnh sửa bằng cắt, xoay, lật, điều chỉnh màu sắc, bộ lọc và đánh dấu.
- Phát video/âm thanh cục bộ và từ nguồn mạng được hỗ trợ; chọn track âm thanh và phụ đề.
- Lấy khung hình video, dùng cửa sổ nổi hoặc cửa sổ phát riêng trên máy tính.

### Tag, tìm kiếm và album

- Gán tag từ menu tập tin, dùng lại tag gần đây/phổ biến và hiển thị tag trong các khung xem.
- Tạo cây tag cha/con, duyệt thư mục và cây dữ liệu với mục con tải theo nhu cầu.
- Tìm theo nhiều tag, lọc/sắp xếp tag và chuyển giữa danh sách, lưới, cây.
- Tạo album thủ công hoặc album thông minh theo quy tắc tên tập tin và thư mục nguồn đã chọn.

### Mạng và không gian SSH

- Kết nối SMB, FTP, SFTP, WebDAV; xem hình thu nhỏ và phát trực tiếp nội dung được hỗ trợ.
- Lưu thông tin kết nối cục bộ để kết nối lại thuận tiện.
- Quản lý hồ sơ SSH với mật khẩu hoặc khóa riêng, nhập khóa OpenSSH/PEM, tạo khóa và sao chép khóa công khai.
- Xác minh dấu vân tay máy chủ; xem cảnh báo rõ ràng khi khóa máy chủ thay đổi.
- Mở terminal tương tác, kết nối lại, xóa nội dung phiên và mở tập tin máy chủ qua SFTP trong tab hiện tại hoặc tab mới.

### Trợ lý AI

- Nhờ CB Agent tìm tập tin bằng ngôn ngữ tự nhiên và đề xuất tổ chức thư mục.
- Tạo tập tin/thư mục và thực hiện các thao tác quản lý qua luồng đề xuất, xác nhận phù hợp.
- Xem xét mục bất thường, nội dung trùng, tên khó hiểu, file đa phương tiện lỗi và mục đặt sai chỗ.
- Yêu cầu đánh giá một file/thư mục trước khi dọn dẹp, với ngữ cảnh về đường dẫn, dung lượng và phân loại.
- Chọn nhà cung cấp AI được hỗ trợ hoặc mô hình GGUF tương thích để chạy trên thiết bị. Khả năng phụ thuộc cấu hình và mô hình.

### Dọn dẹp ổ đĩa Windows

- Quét thư mục lớn, file tạm, bộ nhớ đệm trình duyệt, Thùng rác và các mục có thể dọn dẹp.
- Duyệt cây kết quả linh hoạt, chọn theo mục hoặc danh mục và nhờ CB Agent đánh giá.
- Xem dung lượng ứng dụng đã cài và thông tin sử dụng sẵn có trước khi quyết định xử lý.
- Dùng Thùng rác cho thao tác được hỗ trợ; kiểm tra đường dẫn lỗi và kết quả dọn dẹp.

### File nén, sao lưu và cá nhân hóa

- Duyệt nội dung file nén như thư mục; trích xuất mục đã chọn hoặc toàn bộ.
- Hỗ trợ ZIP, TAR, GZip, BZip2 và các biến thể TAR phổ biến; dùng 7-Zip đã cài cho các thao tác 7z/RAR bổ sung trên Windows.
- Xuất và khôi phục cài đặt/tag bằng gói ZIP.
- Sao lưu lên các tích hợp Google Drive, Dropbox, OneDrive khả dụng qua tài khoản của bạn, kể cả nhiều dịch vụ cùng lúc.
- Chọn sáng/tối, màu nhấn, chế độ xem mặc định, khung xem trước và tùy chọn ảnh thu nhỏ.
- Bản Microsoft Store dùng cơ chế cập nhật của Store; các bản phân phối được hỗ trợ khác có luồng cập nhật riêng.

## Nền tảng và bắt đầu sử dụng

Windows, Android, Linux và macOS có các bản phân phối phù hợp. Một số tính năng phụ thuộc nền tảng: dọn ổ đĩa dành cho Windows; tải torrent hiện dành cho máy tính. Kết nối mạng, sao lưu đám mây, nhà cung cấp AI và mô hình cục bộ có thể cần tài khoản hoặc thiết lập riêng.

Tải bản phù hợp từ [Releases](https://github.com/coolbirdzik/cb-file-hub/releases/latest), Microsoft Store hoặc Google Play. Mở một thư mục, chọn chế độ xem và ghim vị trí thường dùng. Dùng mục Torrent để nhập thư viện và chọn nơi lưu nội dung tải xuống.

Xem [hướng dẫn cài đặt và phát triển](README.md#quick-start), [tài liệu tính năng](docs/features/) và [quy trình gửi Microsoft Store](docs/guides/02-microsoft-store-submission-guide.md).

## Ảnh minh họa và nội dung hai store

Từ thư mục `cb_file_manager/`, dựng lại ảnh torrent tiếng Anh/Việt bằng dữ liệu mẫu:

```bash
flutter test --no-pub tool/capture_torrent_screenshots_test.dart --dart-define=CB_CAPTURE_SCREENSHOTS=true
```

Ảnh được ghi vào `screenshots/features/torrents/en/` và `vi/`; luồng này dựng widget, không mở ứng dụng desktop hay đọc thư viện torrent của người dùng.

Microsoft Store và Google Play dùng chung mô tả ngắn gọn tại [`store/listings/`](store/listings/), mỗi ngôn ngữ của app một bộ (Anh, Việt, Thổ Nhĩ Kỳ, Trung giản thể). Chỉ cần sửa file `.txt` của từng ngôn ngữ; các dòng gạch đầu dòng cũng tạo danh sách tính năng cho Microsoft Store. File `.json` bên cạnh chứa mô tả ngắn, mã ngôn ngữ Google Play và danh sách ảnh chụp/hero art cho Microsoft Store. CI kiểm tra giới hạn ký tự và kích thước ảnh, tạo artifact `store-listings`, rồi cập nhật nội dung (và ảnh với MSIX) khi submit MSIX/AAB. Xem [hướng dẫn nội dung](store/README.md).
