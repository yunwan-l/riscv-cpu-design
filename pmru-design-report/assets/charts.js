// PMRU Design Report - Charts
(function() {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var accent3 = style.getPropertyValue('--accent3').trim();
  var accent4 = style.getPropertyValue('--accent4').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();
  var bg3 = style.getPropertyValue('--bg3').trim();
  var fontFamily = style.getPropertyValue('--font').trim();

  // === Chart 1: Average Hit Rate Comparison ===
  var chartAvg = echarts.init(document.getElementById('chart-avg'), null, { renderer: 'svg' });
  chartAvg.setOption({
    animation: false,
    tooltip: { trigger: 'axis', appendToBody: true },
    grid: { left: '18%', right: '8%', top: 30, bottom: 30 },
    xAxis: {
      type: 'value',
      max: 100,
      axisLabel: { color: muted, fontFamily: fontFamily, formatter: '{value}%' },
      splitLine: { lineStyle: { color: rule } },
      axisLine: { lineStyle: { color: rule } }
    },
    yAxis: {
      type: 'category',
      data: ['LRU', 'SRRIP', 'SHiP', 'APGR', 'PMRU', 'Belady'],
      axisLabel: { color: ink, fontFamily: fontFamily, fontSize: 13 },
      axisLine: { lineStyle: { color: rule } },
      axisTick: { show: false }
    },
    series: [{
      type: 'bar',
      data: [
        { value: 74.77, itemStyle: { color: muted } },
        { value: 75.79, itemStyle: { color: muted } },
        { value: 75.78, itemStyle: { color: muted } },
        { value: 84.54, itemStyle: { color: accent4 } },
        { value: 86.09, itemStyle: { color: accent2 } },
        { value: 87.70, itemStyle: { color: accent } }
      ],
      barWidth: '55%',
      label: {
        show: true,
        position: 'right',
        formatter: '{c}%',
        color: ink,
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: 700
      }
    }]
  });
  window.addEventListener('resize', function() { chartAvg.resize(); });

  // === Chart 2: RR Scenario Comparison ===
  var chartRR = echarts.init(document.getElementById('chart-rr'), null, { renderer: 'svg' });
  chartRR.setOption({
    animation: false,
    tooltip: { trigger: 'axis', appendToBody: true },
    legend: {
      data: ['LRU', 'APGR', 'PMRU', 'Belady'],
      textStyle: { color: ink, fontFamily: fontFamily },
      top: 0
    },
    grid: { left: '10%', right: '5%', top: 40, bottom: 40 },
    xAxis: {
      type: 'category',
      data: ['重复冲突', '深度轮转', '纯轮转', '混合轮转', '热+轮转', '交替相位', '5路冲突', '6路冲突'],
      axisLabel: { color: muted, fontFamily: fontFamily, fontSize: 11, rotate: 30 },
      axisLine: { lineStyle: { color: rule } }
    },
    yAxis: {
      type: 'value',
      max: 100,
      axisLabel: { color: muted, fontFamily: fontFamily, formatter: '{value}%' },
      splitLine: { lineStyle: { color: rule } },
      axisLine: { lineStyle: { color: rule } }
    },
    series: [
      { name: 'LRU', type: 'bar', data: [0, 0, 0, 56.53, 64.24, 66.62, 60, 60], itemStyle: { color: muted }, barGap: '20%' },
      { name: 'APGR', type: 'bar', data: [59.70, 49.83, 59.94, 78.05, 85.60, 86.53, 82.40, 77.83], itemStyle: { color: accent4 } },
      { name: 'PMRU', type: 'bar', data: [73.00, 58.17, 73.26, 76.98, 90.36, 91.00, 84.13, 79.83], itemStyle: { color: accent2 } },
      { name: 'Belady', type: 'bar', data: [74.70, 59.83, 74.94, 78.05, 90.95, 91.56, 88.27, 82.00], itemStyle: { color: accent } }
    ]
  });
  window.addEventListener('resize', function() { chartRR.resize(); });

  // === Chart 3: Variant Comparison ===
  var chartVariant = echarts.init(document.getElementById('chart-variant'), null, { renderer: 'svg' });
  chartVariant.setOption({
    animation: false,
    tooltip: { trigger: 'axis', appendToBody: true },
    grid: { left: '22%', right: '12%', top: 20, bottom: 30 },
    xAxis: {
      type: 'value',
      min: 84,
      max: 86.5,
      axisLabel: { color: muted, fontFamily: fontFamily, formatter: '{value}%' },
      splitLine: { lineStyle: { color: rule } },
      axisLine: { lineStyle: { color: rule } }
    },
    yAxis: {
      type: 'category',
      data: ['T2+A+C+G', '+指数(E)', '+零插入(Z)', 'T4+A+C+G', '+双信号(D3)', '+自适应(AT)', 'T3+A+C+G'],
      axisLabel: { color: ink, fontFamily: fontFamily, fontSize: 12 },
      axisLine: { lineStyle: { color: rule } },
      axisTick: { show: false }
    },
    series: [{
      type: 'bar',
      data: [
        { value: 85.72, itemStyle: { color: accent3 } },
        { value: 85.75, itemStyle: { color: accent3 } },
        { value: 85.87, itemStyle: { color: accent3 } },
        { value: 85.84, itemStyle: { color: accent3 } },
        { value: 85.98, itemStyle: { color: accent4 } },
        { value: 84.87, itemStyle: { color: accent3 } },
        { value: 86.09, itemStyle: { color: accent2 } }
      ],
      barWidth: '55%',
      label: {
        show: true,
        position: 'right',
        formatter: '{c}%',
        color: ink,
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: 700
      },
      markLine: {
        symbol: 'none',
        data: [{ xAxis: 86.09, lineStyle: { color: accent2, type: 'dashed', width: 1 } }],
        label: { show: false }
      }
    }]
  });
  window.addEventListener('resize', function() { chartVariant.resize(); });

  // === Chart 4: Historical Iteration ===
  var chartHistory = echarts.init(document.getElementById('chart-history'), null, { renderer: 'svg' });
  chartHistory.setOption({
    animation: false,
    tooltip: {
      trigger: 'axis',
      appendToBody: true,
      formatter: function(params) {
        var p = params[0];
        return p.name + ': ' + p.value + '%';
      }
    },
    grid: { left: '10%', right: '8%', top: 20, bottom: 40 },
    xAxis: {
      type: 'category',
      data: ['APGR\n(基线)', 'RTAS\nfinal', 'FRS\n统一评分', 'RTAS v4\nHC模式', 'PMRU\nT3+A+C+G', 'RTAS v2\n总是MRU'],
      axisLabel: { color: muted, fontFamily: fontFamily, fontSize: 11 },
      axisLine: { lineStyle: { color: rule } }
    },
    yAxis: {
      type: 'value',
      min: 83,
      max: 87,
      axisLabel: { color: muted, fontFamily: fontFamily, formatter: '{value}%' },
      splitLine: { lineStyle: { color: rule } },
      axisLine: { lineStyle: { color: rule } }
    },
    series: [{
      type: 'bar',
      data: [
        { value: 84.54, itemStyle: { color: accent4 } },
        { value: 84.92, itemStyle: { color: accent4 } },
        { value: 84.69, itemStyle: { color: accent4 } },
        { value: 85.04, itemStyle: { color: accent4 } },
        { value: 86.09, itemStyle: { color: accent2 } },
        { value: 86.36, itemStyle: { color: accent3 } }
      ],
      barWidth: '50%',
      label: {
        show: true,
        position: 'top',
        formatter: '{c}%',
        color: ink,
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: 700
      }
    }]
  });
  window.addEventListener('resize', function() { chartHistory.resize(); });

  // === Mermaid Init ===
  if (typeof mermaid !== 'undefined') {
    mermaid.initialize({ startOnLoad: true, theme: 'dark', securityLevel: 'loose' });
  }
})();
