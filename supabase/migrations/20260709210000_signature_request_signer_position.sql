-- Signer-chosen free-form signature placement for Ask Sign.
-- The signing web page lets the counterparty place their signature anywhere on
-- the document; the position is stored here and consumed by the iOS app when it
-- stamps the counterparty signature (normalized center, origin top-left).
alter table public.pdf_signature_requests
  add column if not exists signature_position_page integer,
  add column if not exists signature_position_x double precision,
  add column if not exists signature_position_y double precision;

alter table public.pdf_signature_requests
  add constraint pdf_signature_requests_position_page_check
    check (signature_position_page is null or signature_position_page >= 0),
  add constraint pdf_signature_requests_position_x_check
    check (signature_position_x is null or (signature_position_x >= 0 and signature_position_x <= 1)),
  add constraint pdf_signature_requests_position_y_check
    check (signature_position_y is null or (signature_position_y >= 0 and signature_position_y <= 1));
