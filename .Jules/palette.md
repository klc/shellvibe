## 2024-08-01 - Missing ARIA/Tooltips on Icon Buttons
**Learning:** Found several `IconButton` components across the application (e.g., in SFTP queue sheet, remote file editor dialog, vault unlock dialog, and identity form dialog) that do not have `tooltip` descriptions. This severely limits accessibility for screen readers and usability for users trying to understand icon-only actions.
**Action:** Always add `tooltip` attributes to `IconButton` widgets if they only contain an `Icon`.
