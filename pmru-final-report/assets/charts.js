// PMRU Final Report Charts
(function() {
  var s = getComputedStyle(document.documentElement);
  var accent = s.getPropertyValue('--accent').trim();
  var accent2 = s.getPropertyValue('--accent2').trim();
  var accent3 = s.getPropertyValue('--accent3').trim();
  var accent4 = s.getPropertyValue('--accent4').trim();
  var ink = s.getPropertyValue('--ink').trim();
  var muted = s.getPropertyValue('--muted').trim();
  var muted2 = s.getPropertyValue('--muted2').trim();
  var rule = s.getPropertyValue('--rule').trim();
  var bg2 = s.getPropertyValue('--bg2').trim();
  var bg3 = s.getPropertyValue('--bg3').trim();
  var ff = s.getPropertyValue('--font').trim();
  var fm = s.getPropertyValue('--font-mono').trim();

  // === Chart 1: Config Comparison ===
  var c1 = echarts.init(document.getElementById('chart-config'), null, {renderer:'svg'});
  c1.setOption({
    animation: false,
    tooltip: {trigger:'axis', appendToBody:true},
    legend: {data:['PMRU命中率','Belady上界'], textStyle:{color:ink, fontFamily:ff}, top:0},
    grid: {left:'12%', right:'8%', top:40, bottom:50},
    xAxis: {
      type:'category',
      data:['LRU\n4w32','APGR\n4w32','PMRU\n4w32','PMRU\n8w64','PMRU\n8w64+V8','PF16+SB'],
      axisLabel:{color:muted, fontFamily:ff, fontSize:11, interval:0},
      axisLine:{lineStyle:{color:rule}}
    },
    yAxis: {
      type:'value', min:70, max:100,
      axisLabel:{color:muted, fontFamily:ff, formatter:'{value}%'},
      splitLine:{lineStyle:{color:rule}},
      axisLine:{lineStyle:{color:rule}}
    },
    series: [
      {name:'PMRU命中率', type:'bar', barWidth:'40%',
       data:[74.77, 84.54, 86.09, 94.68, 94.68, 98.99],
       itemStyle:{color:function(p){return p.dataIndex>=3?accent2:accent4}},
       label:{show:true, position:'top', formatter:'{c}%', color:ink, fontFamily:fm, fontSize:11, fontWeight:700}},
      {name:'Belady上界', type:'line', data:[87.70, 87.70, 87.70, 94.68, 94.68, 94.68],
       itemStyle:{color:accent4}, lineStyle:{type:'dashed', width:2},
       symbol:'diamond', symbolSize:8}
    ]
  });
  window.addEventListener('resize', function(){c1.resize();});

  // === Chart 2: Contribution Breakdown ===
  var c2 = echarts.init(document.getElementById('chart-contrib'), null, {renderer:'svg'});
  c2.setOption({
    animation: false,
    tooltip:{trigger:'item', appendToBody:true},
    legend:{textStyle:{color:ink, fontFamily:ff}, bottom:0},
    series:[{
      type:'funnel',
      left:'10%', right:'10%', top:10, bottom:40,
      minSize:'30%',
      label:{show:true, color:ink, fontFamily:fm, fontSize:12, formatter:'{b}: +{c}%'},
      data:[
        {value:8.59, name:'8路64组(容量)', itemStyle:{color:accent2}},
        {value:3.42, name:'PF16预取', itemStyle:{color:accent4}},
        {value:0.89, name:'流式旁路', itemStyle:{color:accent3}},
        {value:1.55, name:'PMRU替换', itemStyle:{color:accent}},
        {value:0.00, name:'Victim Cache', itemStyle:{color:muted2}},
      ].reverse()
    }]
  });
  window.addEventListener('resize', function(){c2.resize();});

  // === Chart 3: RR Scenario Comparison ===
  var c3 = echarts.init(document.getElementById('chart-rr'), null, {renderer:'svg'});
  c3.setOption({
    animation:false,
    tooltip:{trigger:'axis', appendToBody:true},
    legend:{data:['LRU 4w32','APGR 4w32','PMRU 4w32','PMRU 8w64','PF16+SB','Belady 8w64'],
            textStyle:{color:ink, fontFamily:ff}, top:0},
    grid:{left:'8%', right:'5%', top:40, bottom:50},
    xAxis:{
      type:'category',
      data:['5路冲突','6路冲突','深度轮转','纯轮转','混合轮转','热+轮转','交替相位','重复冲突'],
      axisLabel:{color:muted, fontFamily:ff, fontSize:10, rotate:30},
      axisLine:{lineStyle:{color:rule}}
    },
    yAxis:{
      type:'value', min:0, max:100,
      axisLabel:{color:muted, fontFamily:ff, formatter:'{value}%'},
      splitLine:{lineStyle:{color:rule}},
      axisLine:{lineStyle:{color:rule}}
    },
    series:[
      {name:'LRU 4w32', type:'bar', data:[60,60,0,0,56.53,64.24,66.62,0], itemStyle:{color:muted}},
      {name:'APGR 4w32', type:'bar', data:[82.4,77.83,49.83,59.94,78.05,85.60,86.53,59.70], itemStyle:{color:accent4}},
      {name:'PMRU 4w32', type:'bar', data:[84.13,79.83,58.17,73.26,76.98,90.36,91.00,73.00], itemStyle:{color:accent3}},
      {name:'PMRU 8w64', type:'bar', data:[97.33,96.00,99.67,99.90,99.36,99.83,99.84,99.50], itemStyle:{color:accent2}},
      {name:'PF16+SB', type:'bar', data:[98.67,98.00,99.87,99.90,99.36,99.86,99.87,99.67], itemStyle:{color:accent}},
      {name:'Belady 8w64', type:'line', data:[97.33,96.00,99.67,99.90,99.36,99.83,99.84,99.50],
       itemStyle:{color:accent4}, lineStyle:{type:'dashed'}, symbol:'none'}
    ]
  });
  window.addEventListener('resize', function(){c3.resize();});

  // === Chart 4: Prefetch Impact ===
  var c4 = echarts.init(document.getElementById('chart-pf'), null, {renderer:'svg'});
  c4.setOption({
    animation:false,
    tooltip:{trigger:'axis', appendToBody:true},
    legend:{data:['无预取','PF4','PF16+SB'], textStyle:{color:ink, fontFamily:ff}, top:0},
    grid:{left:'12%', right:'8%', top:40, bottom:40},
    xAxis:{
      type:'category',
      data:['顺序扫描','流式后循环','中断模拟','工作集切换','Zipf分布'],
      axisLabel:{color:muted, fontFamily:ff, fontSize:11},
      axisLine:{lineStyle:{color:rule}}
    },
    yAxis:{
      type:'value',
      axisLabel:{color:muted, fontFamily:ff, formatter:'{value}%'},
      splitLine:{lineStyle:{color:rule}},
      axisLine:{lineStyle:{color:rule}}
    },
    series:[
      {name:'无预取', type:'bar', data:[0, 93.28, 96.64, 99.00, 88.40], itemStyle:{color:accent4}, barGap:'20%'},
      {name:'PF4', type:'bar', data:[79.95, 98.44, 98.91, 99.41, 88.95], itemStyle:{color:accent3}},
      {name:'PF16+SB', type:'bar', data:[99.90, 99.53, 98.73, 99.90, 91.00], itemStyle:{color:accent2}}
    ]
  });
  window.addEventListener('resize', function(){c4.resize();});

  // === Mermaid ===
  if (typeof mermaid !== 'undefined') {
    mermaid.initialize({startOnLoad:true, theme:'dark', securityLevel:'loose'});
  }
})();
