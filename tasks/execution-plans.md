# ProTrading AI V2.1 — bản đồ kế hoạch thực thi

Hai kế hoạch thực thi độc lập:

1. **Web:** `tasks/web-completion-plan.md` — thực hiện và nghiệm thu Web,
   backend, Rules và provider contract cần cho Web.
2. **Mobile:** `tasks/mobile-completion-plan.md` — bắt đầu từ contract Web đã
   nghiệm thu, hoàn thiện Android/iOS, platform integration, signing và store
   rollout.

`tasks/plan.md`, `tasks/todo.md`, `tasks/requirements-v2.1.md` và
`tasks/acceptance-matrix.md` tiếp tục là nguồn truy vết Master. Chúng không phải
kế hoạch thực thi thứ ba và không được dùng để cộng lại các việc Web/Mobile đã
được tách.

Khi Web đạt checkpoint cuối, đóng kế hoạch Web và chỉ còn checklist `MB01`–
`MB40` của kế hoạch Mobile. Shared backend/API/Rules đã được Web nghiệm thu là
đầu vào bất biến cho Mobile, trừ khi Mobile phát hiện một lỗi có test hồi quy
chứng minh cần sửa.
