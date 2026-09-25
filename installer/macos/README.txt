CB File Hub for macOS
=====================

ENGLISH

1. Drag "CB File Hub" onto the "Applications" folder.
2. Open "CB File Hub" from Applications. macOS says it cannot verify the
   app: click "Done" (do NOT click "Move to Trash").
3. Open System Settings > Privacy & Security, scroll down to the Security
   section and click "Open Anyway" next to the "CB File Hub" message.
   (The button only stays there for about an hour after step 2.)
4. Confirm with "Open Anyway" and your password. From then on the app opens
   normally.

5. When the app asks for Full Disk Access, click "Grant Permission". System
   Settings opens on the Full Disk Access list with a CB File Hub icon
   beside it: drag the icon into the list, approve with Touch ID or your
   password, then choose "Quit & Reopen". If CB File Hub is already listed,
   just switch it on. After an update you may need to switch it on again.

Why: the app is not notarized with a paid Apple Developer ID, so macOS asks
you to allow it once.

If macOS says the app "is damaged", run this in Terminal and open it again:
    xattr -dr com.apple.quarantine "/Applications/CB File Hub.app"


TIẾNG VIỆT

1. Kéo "CB File Hub" vào thư mục "Applications".
2. Mở "CB File Hub" từ Applications. macOS báo không xác minh được ứng dụng:
   bấm "Done" / "Xong" (KHÔNG bấm "Move to Trash").
3. Mở System Settings (Cài đặt hệ thống) > Privacy & Security (Quyền riêng tư
   & Bảo mật), kéo xuống mục Security (Bảo mật) và bấm "Open Anyway" (Vẫn mở)
   cạnh dòng thông báo về "CB File Hub".
   (Nút này chỉ hiện trong khoảng một giờ sau bước 2.)
4. Xác nhận "Open Anyway" và nhập mật khẩu. Từ lần sau ứng dụng mở bình
   thường.

5. Khi ứng dụng xin quyền Full Disk Access (Truy cập toàn bộ ổ đĩa), bấm
   "Cấp quyền". Cài đặt hệ thống mở danh sách Full Disk Access, bên cạnh có
   biểu tượng CB File Hub: kéo biểu tượng vào danh sách, xác nhận bằng
   Touch ID hoặc mật khẩu, rồi chọn "Quit & Reopen" (Thoát & Mở lại). Nếu
   CB File Hub đã có trong danh sách thì chỉ cần bật công tắc. Sau khi cập
   nhật có thể phải bật lại.

Lý do: ứng dụng chưa được notarize bằng Apple Developer ID trả phí, nên macOS
yêu cầu bạn cho phép một lần.

Nếu macOS báo ứng dụng "bị hỏng" (damaged), chạy lệnh sau trong Terminal rồi
mở lại:
    xattr -dr com.apple.quarantine "/Applications/CB File Hub.app"
