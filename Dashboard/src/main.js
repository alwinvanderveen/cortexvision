const POLL_INTERVAL = 1500;
let lastTimestamp = null;
let currentFilter = 'all';
let currentCategory = 'all';
const expandedTests = new Set();

async function fetchJSON(path) {
  try {
    const res = await fetch(`/api/${path}?_=${Date.now()}`);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

function formatDuration(seconds) {
  if (seconds == null) return '—';
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

function formatShortTime(isoString) {
  const d = new Date(isoString);
  return d.toLocaleString('nl-NL', {
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  });
}

function getCoverageColor(pct, threshold) {
  if (pct >= threshold) return '#34d399';
  if (pct >= threshold - 10) return '#fbbf24';
  return '#f87171';
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

  const angle = (pct / 100) * Math.PI;
  const endX = 100 - 80 * Math.cos(angle);
  const endY = 100 - 80 * Math.sin(angle);
  const largeArc = 0; // Always short arc — fill never exceeds the 180° semicircle

  const fill = document.getElementById('gauge-fill');
  fill.setAttribute('d', `M20,100 A80,80 0 ${largeArc},1 ${endX},${endY}`);
  fill.style.stroke = color;

  const text = document.getElementById('gauge-text');
  text.textContent = `${pct.toFixed(1)}%`;
  text.style.fill = color;

  const container = document.getElementById('coverage-files');
  if (coverage.files.length === 0) {
    container.innerHTML = '<p class="muted">No file coverage data available</p>';
    return;
  }

  let html = `
    <table class="coverage-table">
      <thead><tr><th>File</th><th>Coverage</th><th>Lines</th></tr></thead>
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

function getCategory(test) {
  return test.catalog?.category || test.suiteName || 'Uncategorized';
}

function categoryClass(category) {
  return 'cat-' + category.toLowerCase().replace(/[^a-z]/g, '');
}

function renderCategoryFilters(tests) {
  const categories = [...new Set(tests.map(getCategory))].sort();
  const container = document.getElementById('category-filters');
  let html = '<span class="filter-label">Category</span>';
  html += `<button class="cat-btn ${currentCategory === 'all' ? 'active' : ''}" data-category="all">All</button>`;
  for (const cat of categories) {
    html += `<button class="cat-btn ${currentCategory === cat ? 'active' : ''}" data-category="${cat}">${cat}</button>`;
  }
  container.innerHTML = html;

  container.querySelectorAll('.cat-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      container.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentCategory = btn.dataset.category;
      if (cachedData) renderTests(cachedData.tests);
    });
  });
}

function renderTests(tests) {
  const container = document.getElementById('test-results');
  let filtered = currentFilter === 'all' ? tests : tests.filter(t => t.status === currentFilter);
  if (currentCategory !== 'all') {
    filtered = filtered.filter(t => getCategory(t) === currentCategory);
  }

  if (filtered.length === 0) {
    container.innerHTML = '<div class="empty">No tests match the current filter</div>';
    return;
  }

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
      const testKey = test.nodeIdentifier || `${test.suiteName}/${test.name}`;
      const isExpanded = expandedTests.has(testKey) || (test.status === 'FAIL' && !expandedTests.has(`_dismissed_${testKey}`));

      const cat = getCategory(test);
      html += `
        <div class="test-card ${test.status.toLowerCase()} ${isExpanded ? 'expanded' : ''}" data-status="${test.status}" data-test-key="${testKey}">
          <div class="test-header">
            ${statusIcon(test.status)}
            <span class="test-name">${test.name}</span>
            <span class="category-badge ${categoryClass(cat)}">${cat}</span>
            ${hasCatalog ? `<span class="test-id">${test.catalog.id}</span>` : ''}
          </div>
          <div class="test-details ${isExpanded ? 'show' : ''}">
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

  // Attach click handlers via event delegation
  container.querySelectorAll('.test-header').forEach(header => {
    header.addEventListener('click', () => {
      const card = header.parentElement;
      const key = card.dataset.testKey;
      if (expandedTests.has(key)) {
        expandedTests.delete(key);
        card.classList.remove('expanded');
        card.querySelector('.test-details').classList.remove('show');
      } else {
        expandedTests.add(key);
        expandedTests.delete(`_dismissed_${key}`);
        card.classList.add('expanded');
        card.querySelector('.test-details').classList.add('show');
      }
    });
  });
}

function renderHistory(history) {
  const container = document.getElementById('run-history');
  if (!history || history.length === 0) {
    container.innerHTML = '<p class="muted">No previous runs recorded</p>';
    return;
  }

  // Show most recent first, max 20
  const runs = history.slice(-20).reverse();

  let html = `
    <table class="history-table">
      <thead>
        <tr>
          <th>Run</th>
          <th>Time</th>
          <th>Total</th>
          <th>Pass</th>
          <th>Fail</th>
          <th>Skip</th>
          <th>Coverage</th>
          <th>Trend</th>
        </tr>
      </thead>
      <tbody>
  `;

  for (let i = 0; i < runs.length; i++) {
    const run = runs[i];
    const prevRun = runs[i + 1];
    const isLatest = i === 0;
    const allPass = run.summary.failed === 0;
    const coverageColor = getCoverageColor(run.coveragePercentage, 85);

    // Coverage trend
    let trend = '';
    if (prevRun) {
      const diff = run.coveragePercentage - prevRun.coveragePercentage;
      if (Math.abs(diff) > 0.01) {
        const arrow = diff > 0 ? '↑' : '↓';
        const trendColor = diff > 0 ? '#34d399' : '#f87171';
        trend = `<span style="color:${trendColor}">${arrow} ${Math.abs(diff).toFixed(1)}%</span>`;
      } else {
        trend = '<span class="muted">—</span>';
      }
    } else {
      trend = '<span class="muted">—</span>';
    }

    html += `
      <tr class="${isLatest ? 'history-latest' : ''} ${!allPass ? 'history-has-failures' : ''}">
        <td>${isLatest ? '<strong>#' + history.length + '</strong>' : '#' + (history.length - i)}</td>
        <td>${formatShortTime(run.timestamp)}</td>
        <td>${run.summary.total}</td>
        <td class="pass-cell">${run.summary.passed}</td>
        <td class="${run.summary.failed > 0 ? 'fail-cell' : ''}">${run.summary.failed}</td>
        <td>${run.summary.skipped}</td>
        <td><span class="coverage-badge" style="background:${coverageColor}">${run.coveragePercentage.toFixed(1)}%</span></td>
        <td>${trend}</td>
      </tr>
    `;
  }

  html += '</tbody></table>';
  container.innerHTML = html;
}

function setupFilters() {
  document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.dataset.filter;
      if (cachedData) renderTests(cachedData.tests);
    });
  });
}

let cachedData = null;

async function refresh() {
  const [data, history] = await Promise.all([
    fetchJSON('dashboard.json'),
    fetchJSON('history.json'),
  ]);

  if (data) {
    const isNew = data.timestamp !== lastTimestamp;
    cachedData = data;

    if (isNew) {
      lastTimestamp = data.timestamp;
      document.getElementById('timestamp').textContent = formatTimestamp(data.timestamp);
      renderSummary(data.summary);
      renderCoverage(data.coverage);
      renderCategoryFilters(data.tests);
      renderTests(data.tests);

      if (history) {
        renderHistory(history);
      }
    }
  } else if (!cachedData) {
    // First load, no data yet — keep waiting message
  }
}

setupFilters();
refresh();
setInterval(refresh, POLL_INTERVAL);
