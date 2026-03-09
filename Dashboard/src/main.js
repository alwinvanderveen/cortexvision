const POLL_INTERVAL = 1500;
let lastTimestamp = null;
let currentFilter = 'all';

async function fetchDashboard() {
  try {
    const res = await fetch('/dashboard.json?' + Date.now());
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

function formatDuration(seconds) {
  if (seconds < 1) return `${Math.round(seconds * 1000)}ms`;
  return `${seconds.toFixed(2)}s`;
}

function formatTimestamp(isoString) {
  const d = new Date(isoString);
  return d.toLocaleString('nl-NL', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  });
}

function getCoverageColor(pct, threshold) {
  if (pct >= threshold) return '#34d399';      // green
  if (pct >= threshold - 10) return '#fbbf24';  // orange
  return '#f87171';                              // red
}

function statusIcon(status) {
  switch (status) {
    case 'PASS': return '<span class="status-icon pass">✓</span>';
    case 'FAIL': return '<span class="status-icon fail">✗</span>';
    case 'SKIP': return '<span class="status-icon skip">⊘</span>';
    default: return '<span class="status-icon">?</span>';
  }
}

function renderSummary(summary) {
  document.getElementById('total-count').textContent = summary.total;
  document.getElementById('pass-count').textContent = summary.passed;
  document.getElementById('fail-count').textContent = summary.failed;
  document.getElementById('skip-count').textContent = summary.skipped;
  document.getElementById('duration').textContent = formatDuration(summary.duration);
}

function renderCoverage(coverage) {
  const pct = coverage.percentage;
  const color = getCoverageColor(pct, coverage.threshold);

  // Gauge arc: 0% = full left, 100% = full right
  // Arc from (20,100) to (180,100), radius 80
  const angle = (pct / 100) * Math.PI;
  const endX = 100 - 80 * Math.cos(angle);
  const endY = 100 - 80 * Math.sin(angle);
  const largeArc = pct > 50 ? 1 : 0;

  const fill = document.getElementById('gauge-fill');
  fill.setAttribute('d', `M20,100 A80,80 0 ${largeArc},1 ${endX},${endY}`);
  fill.style.stroke = color;

  const text = document.getElementById('gauge-text');
  text.textContent = `${pct.toFixed(1)}%`;
  text.style.fill = color;

  // File coverage table
  const container = document.getElementById('coverage-files');
  if (coverage.files.length === 0) {
    container.innerHTML = '<p class="muted">No file coverage data available</p>';
    return;
  }

  let html = `
    <table class="coverage-table">
      <thead>
        <tr><th>File</th><th>Coverage</th><th>Lines</th></tr>
      </thead>
      <tbody>
  `;
  for (const file of coverage.files) {
    const fileColor = getCoverageColor(file.lineCoverage, coverage.threshold);
    const shortPath = file.path.split('/').slice(-2).join('/');
    html += `
      <tr>
        <td class="file-path">${shortPath}</td>
        <td><span class="coverage-badge" style="background:${fileColor}">${file.lineCoverage.toFixed(1)}%</span></td>
        <td class="muted">${file.coveredLines}/${file.executableLines}</td>
      </tr>
    `;
  }
  html += '</tbody></table>';
  container.innerHTML = html;
}

function renderTests(tests) {
  const container = document.getElementById('test-results');
  const filtered = currentFilter === 'all' ? tests : tests.filter(t => t.status === currentFilter);

  if (filtered.length === 0) {
    container.innerHTML = '<div class="empty">No tests match the current filter</div>';
    return;
  }

  // Group by suite
  const suites = {};
  for (const test of filtered) {
    const suite = test.suiteName || 'Ungrouped';
    if (!suites[suite]) suites[suite] = [];
    suites[suite].push(test);
  }

  let html = '';
  for (const [suiteName, suiteTests] of Object.entries(suites)) {
    html += `<div class="suite"><h3 class="suite-name">${suiteName}</h3>`;

    for (const test of suiteTests) {
      const hasCatalog = test.catalog != null;
      const expanded = test.status === 'FAIL';

      html += `
        <div class="test-card ${test.status.toLowerCase()}" data-status="${test.status}">
          <div class="test-header" onclick="this.parentElement.classList.toggle('expanded')">
            ${statusIcon(test.status)}
            <span class="test-name">${test.name}</span>
            ${hasCatalog ? `<span class="test-id">${test.catalog.id}</span>` : ''}
            <span class="test-duration">${formatDuration(test.duration)}</span>
          </div>
          <div class="test-details ${expanded ? 'show' : ''}">
            ${hasCatalog ? `
              <div class="detail-grid">
                <div class="detail-item">
                  <div class="detail-label">Functional</div>
                  <div class="detail-value">${test.catalog.functional}</div>
                </div>
                <div class="detail-item">
                  <div class="detail-label">Technical</div>
                  <div class="detail-value">${test.catalog.technical}</div>
                </div>
                <div class="detail-item">
                  <div class="detail-label">Input</div>
                  <div class="detail-value"><code>${test.catalog.input}</code></div>
                </div>
                <div class="detail-item">
                  <div class="detail-label">Expected Output</div>
                  <div class="detail-value"><code>${test.catalog.expectedOutput}</code></div>
                </div>
                ${test.catalog.tags.length > 0 ? `
                  <div class="detail-item">
                    <div class="detail-label">Tags</div>
                    <div class="detail-value">${test.catalog.tags.map(t => `<span class="tag">${t}</span>`).join(' ')}</div>
                  </div>
                ` : ''}
              </div>
            ` : '<p class="muted">No catalog entry found for this test. Add it to TestCatalog.json.</p>'}
            ${test.message ? `
              <div class="test-message">
                <div class="detail-label">Error Message</div>
                <pre>${test.message}</pre>
              </div>
            ` : ''}
          </div>
        </div>
      `;
    }

    html += '</div>';
  }

  container.innerHTML = html;
}

function setupFilters() {
  document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.dataset.filter;
      refresh();
    });
  });
}

let cachedData = null;

async function refresh() {
  const data = await fetchDashboard();
  if (data) {
    cachedData = data;
    if (data.timestamp !== lastTimestamp) {
      lastTimestamp = data.timestamp;
      document.getElementById('timestamp').textContent = formatTimestamp(data.timestamp);
    }
    renderSummary(data.summary);
    renderCoverage(data.coverage);
    renderTests(data.tests);
  } else if (cachedData) {
    renderTests(cachedData.tests);
  }
}

setupFilters();
refresh();
setInterval(refresh, POLL_INTERVAL);
