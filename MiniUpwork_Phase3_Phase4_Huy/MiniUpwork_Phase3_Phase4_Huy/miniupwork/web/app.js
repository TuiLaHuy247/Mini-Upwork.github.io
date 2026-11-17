"use strict";

const byId = (id) => document.getElementById(id);
const searchForm = byId("search-form");
const proposalForm = byId("proposal-form");
const sendButton = byId("send");
const list = byId("jobs");
const drawer = byId("job-drawer");
const filterFields = [byId("category"), byId("skill"), byId("job-type")];
const pageSize = 8;
const usd = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "USD", currencyDisplay: "code" });
const integers = new Intl.NumberFormat("vi-VN");
const dateFormat = new Intl.DateTimeFormat("vi-VN", {
  day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Ho_Chi_Minh",
});

const state = {
  params: new URLSearchParams(), offset: 0, total: 0, current: null,
  search: null, detail: null, saving: false, references: false,
};

async function request(path, options) {
  const response = await fetch(path, options);
  const body = await response.json().catch(() => null);
  if (!response.ok || body === null) {
    const error = new Error("API request failed");
    error.code = body?.detail?.code;
    error.status = response.status;
    throw error;
  }
  return body;
}

function notice(element, message = "", tone = "info") {
  element.textContent = message;
  element.hidden = !message;
  element.dataset.state = tone;
}

function connection(ready) {
  const status = byId("connection");
  status.dataset.state = ready ? "ready" : "error";
  status.textContent = ready ? "Đã kết nối CSDL" : "CSDL chưa sẵn sàng";
}

function fillOptions(select, rows, value, label) {
  const options = rows.map((row) => new Option(label(row), String(row[value])));
  select.replaceChildren(select.options[0], ...options);
}

async function loadReferences() {
  try {
    const refs = await request("/reference-data");
    fillOptions(byId("category"), refs.categories, "category_id", (item) => item.category_name);
    fillOptions(byId("skill"), refs.skills, "skill_id", (item) => item.skill_name);
    fillOptions(byId("freelancer"), refs.freelancers.filter((item) => item.status === "ACTIVE"),
      "freelancer_id", (item) => `${item.full_name} · #${item.freelancer_id}`);
    state.references = true;
    connection(true);
  } catch {
    state.references = false;
    connection(false);
  }
  updateSubmit();
}

function formatPrice(job) {
  const pricing = job.pricing;
  return job.job_type === "HOURLY"
    ? `${usd.format(pricing.rate_min)} – ${usd.format(pricing.rate_max)} / giờ`
    : usd.format(pricing.budget_amount);
}

function typeName(job) {
  return job.job_type === "HOURLY" ? "Theo giờ" : "Trọn gói";
}

function textElement(tag, className, text) {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  return element;
}

function updateSubmit() {
  sendButton.disabled = state.saving || !state.current || !state.references;
  sendButton.textContent = state.saving ? "Đang gửi…" : "Gửi đề xuất";
}

function resetDetail(message) {
  state.detail?.abort();
  state.current = null;
  proposalForm.reset();
  proposalForm.hidden = true;
  notice(byId("proposal-message"));
  byId("job-content").hidden = true;
  byId("job-meta").hidden = true;
  byId("detail-title").textContent = "Chi tiết công việc";
  notice(byId("detail-message"), message);
  updateSubmit();
}

function displayJob(job) {
  const hourly = job.job_type === "HOURLY";
  byId("job-meta").textContent = `#${job.job_id} · ${job.category_name} · ${typeName(job)}`;
  byId("job-meta").hidden = false;
  byId("detail-title").textContent = job.title;
  byId("client").textContent = `${job.client_name} · #${job.client_id}`;
  byId("price-label").textContent = hourly ? "Đơn giá" : "Ngân sách";
  byId("price").textContent = formatPrice(job);
  byId("description").textContent = job.description;
  byId("job-skills").replaceChildren(...job.skills.map((skill) =>
    textElement("li", "", `${skill.skill_name} · Mức ${skill.required_level}`)));
  byId("offer-label").textContent = hourly ? "Đơn giá đề xuất (USD/giờ)" : "Tổng giá đề xuất (USD)";
  byId("show-proposal").hidden = job.status !== "OPEN";
  notice(byId("detail-message"), job.status !== "OPEN" ? "Công việc này đã ngừng nhận đề xuất." : "");
  byId("job-content").hidden = false;
  updateSubmit();
}

async function selectJob(id) {
  resetDetail("Đang đọc chi tiết công việc…");
  const controller = new AbortController();
  state.detail = controller;
  drawer.showModal();
  drawer.scrollTop = 0;
  try {
    const job = await request(`/jobs/${id}`, { signal: controller.signal });
    if (state.detail !== controller || controller.signal.aborted) return;
    state.current = job;
    displayJob(job);
  } catch (error) {
    if (error.name === "AbortError" || state.detail !== controller) return;
    notice(byId("detail-message"), "Không đọc được chi tiết. Hãy chọn lại công việc.", "error");
    if (error.status === 503) connection(false);
  }
}

function displayActiveFilters() {
  const chips = byId("active-filters");
  chips.replaceChildren();
  for (const field of filterFields) {
    const value = state.params.get(field.name);
    if (!value) continue;
    const label = Array.from(field.options).find((option) => option.value === value)?.label || value;
    const item = document.createElement("li");
    const remove = textElement("button", "active-filter", label);
    remove.type = "button";
    remove.setAttribute("aria-label", `Bỏ bộ lọc ${label}`);
    const mark = textElement("span", "", "×");
    mark.setAttribute("aria-hidden", "true");
    remove.append(mark);
    remove.addEventListener("click", () => {
      field.value = "";
      state.params.delete(field.name);
      state.offset = 0;
      searchForm.elements.q.focus();
      search();
    });
    item.append(remove);
    chips.append(item);
  }
  chips.hidden = chips.childElementCount === 0;
  byId("clear-filters").hidden = chips.hidden;
}

function displayResults(result) {
  state.total = result.total;
  list.replaceChildren(...result.items.map((job) => {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "job-button";
    button.setAttribute("aria-haspopup", "dialog");
    button.setAttribute("aria-controls", "job-drawer");
    const arrow = textElement("span", "job-arrow", "↗");
    arrow.setAttribute("aria-hidden", "true");
    button.append(
      textElement("span", "job-meta-line", `${typeName(job)} · ${dateFormat.format(new Date(job.posted_at))}`),
      textElement("span", "job-name", job.title),
      textElement("span", "job-price", formatPrice(job)),
      textElement("span", "job-excerpt", job.description),
      textElement("span", "job-category", job.category_name),
      arrow,
    );
    button.addEventListener("click", () => selectJob(job.job_id));
    item.append(button);
    return item;
  }));
  byId("result-count").textContent = `${integers.format(result.total)} công việc`;
  byId("feed-sort").hidden = result.total === 0;
  byId("pagination").hidden = result.total <= pageSize;
  byId("previous").disabled = state.offset === 0;
  byId("next").disabled = state.offset + pageSize >= result.total;
  byId("page-label").textContent = `Trang ${Math.floor(state.offset / pageSize) + 1} / ${Math.ceil(result.total / pageSize)}`;

  if (!result.items.length) {
    notice(byId("search-message"), "Không có công việc khớp bộ lọc.");
    return;
  }
  notice(byId("search-message"));
}

async function search() {
  state.search?.abort();
  const controller = new AbortController();
  state.search = controller;
  const keyword = state.params.get("q");
  byId("results-title").textContent = keyword ? `Kết quả cho “${keyword}”` : "Công việc đang mở";
  displayActiveFilters();
  list.setAttribute("aria-busy", "true");
  list.inert = true;
  byId("previous").disabled = true;
  byId("next").disabled = true;
  notice(byId("search-message"), "Đang tìm công việc…");

  const params = new URLSearchParams(state.params);
  params.set("limit", pageSize);
  params.set("offset", state.offset);
  try {
    const result = await request(`/jobs?${params}`, { signal: controller.signal });
    if (state.search !== controller || controller.signal.aborted) return;
    connection(true);
    if (result.total && !result.items.length && state.offset > 0) {
      state.offset = Math.floor((result.total - 1) / pageSize) * pageSize;
      search();
      return;
    }
    displayResults(result);
  } catch (error) {
    if (error.name === "AbortError" || state.search !== controller) return;
    list.replaceChildren();
    byId("result-count").textContent = "";
    byId("feed-sort").hidden = true;
    byId("pagination").hidden = true;
    notice(byId("search-message"), "Không tải được công việc. Kiểm tra kết nối rồi bấm Tìm việc để thử lại.", "error");
    if (error.status === 503 || error instanceof TypeError) connection(false);
  } finally {
    if (state.search === controller) {
      list.removeAttribute("aria-busy");
      list.inert = false;
    }
  }
}

function setFiltersExpanded(expanded) {
  const toggle = byId("toggle-filters");
  const options = byId("filter-options");
  if (!expanded && toggle.getClientRects().length && options.contains(document.activeElement)) toggle.focus();
  toggle.setAttribute("aria-expanded", String(expanded));
  options.dataset.expanded = String(expanded);
}

searchForm.addEventListener("submit", (event) => {
  event.preventDefault();
  state.params = new URLSearchParams();
  for (const [name, value] of new FormData(searchForm)) {
    if (value.trim()) state.params.set(name, value.trim());
  }
  state.offset = 0;
  setFiltersExpanded(false);
  if (!state.references) loadReferences();
  search();
});
byId("toggle-filters").addEventListener("click", (event) => {
  setFiltersExpanded(event.currentTarget.getAttribute("aria-expanded") !== "true");
});
byId("clear-filters").addEventListener("click", () => {
  for (const field of filterFields) {
    field.value = "";
    state.params.delete(field.name);
  }
  state.offset = 0;
  searchForm.elements.q.focus();
  search();
});
byId("previous").addEventListener("click", () => {
  state.offset = Math.max(0, state.offset - pageSize);
  search();
});
byId("next").addEventListener("click", () => {
  if (state.offset + pageSize < state.total) {
    state.offset += pageSize;
    search();
  }
});

byId("close-job").addEventListener("click", () => drawer.close());
drawer.addEventListener("click", (event) => {
  if (event.target === drawer) drawer.close();
});
drawer.addEventListener("close", () => {
  if (!drawer.open) resetDetail();
});
byId("show-proposal").addEventListener("click", (event) => {
  proposalForm.hidden = false;
  event.currentTarget.hidden = true;
  byId("freelancer").focus({ preventScroll: true });
  proposalForm.scrollIntoView({ block: "start" });
});

const rejectionMessages = {
  duplicate_record: "Freelancer này đã có đề xuất cho công việc. CSDL từ chối tạo bản ghi trùng.",
  self_bid: "Không thể ứng tuyển công việc do chính tài khoản này đăng.",
  state_conflict: "Công việc hiện không nhận đề xuất. Hãy tìm một công việc đang mở.",
  inactive_profile: "Tài khoản freelancer này đã ngừng hoạt động.",
  not_found: "Không tìm thấy công việc hoặc hồ sơ freelancer.",
  concurrent_change: "Dữ liệu vừa thay đổi. Hãy thử gửi lại.",
};

proposalForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const job = state.current;
  if (!job || job.status !== "OPEN" || state.saving || !state.references) return;

  const body = {
    freelancer_id: Number(byId("freelancer").value),
    cover_letter: byId("letter").value.trim(),
    offered_amount: byId("offer").value,
  };
  const feedback = byId("proposal-message");
  if (!body.cover_letter) {
    notice(feedback, "Nhập thư giới thiệu trước khi gửi.", "error");
    byId("letter").focus();
    return;
  }

  state.saving = true;
  updateSubmit();
  notice(feedback, "Đang ghi đề xuất vào CSDL…");
  try {
    const result = await request(`/jobs/${job.job_id}/proposals`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (state.current === job) {
      notice(feedback, `Đã lưu đề xuất #${result.proposal_id} · ${result.status}.`, "success");
    }
  } catch (error) {
    if (error.status === 503 || error instanceof TypeError) connection(false);
    if (state.current !== job) return;
    const message = rejectionMessages[error.code] || (error.status === 422
      ? "Kiểm tra tài khoản, mức đề xuất và thư giới thiệu rồi thử lại."
      : "Chưa xác nhận được đề xuất đã lưu. Hãy kiểm tra kết nối trước khi gửi lại.");
    notice(feedback, message, "error");
  } finally {
    state.saving = false;
    updateSubmit();
  }
});

loadReferences();
search();
