#!/bin/sh
export TITLE="Verwaltung &gt; Infos: Firewall - SVG Baumstruktur (Hierarchie)"
. /usr/lib/www/page-pre.sh ${0%/*}

cat <<EOM
<h2>${TITLE}</h2>
<br>
EOM

cat <<'EOM'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <title>Firewall SVG Baumstruktur</title>
  <style>
    body { margin: 0; padding: 0; }
    /* Container mit fester Höhe - isoliertes, weißes Fenster */
    #graph { width: 100%; height: 800px; border: 1px solid #ccc; background: #fff; position: relative; overflow: hidden; }
    svg { width: 100%; height: 100%; }
    .node rect {
      width: 120px;
      height: 50px;
      rx: 10;
      ry: 10;
      stroke-width: 3px;
    }
    .node text {
      font-family: sans-serif;
      font-size: 10px;
      fill: #333;
      pointer-events: none;
    }
    .link {
      fill: none;
      stroke: #999;
      stroke-width: 2px;
      marker-end: url(#arrow);
    }
    .popup {
      position: absolute;
      background: #fff;
      border: 1px solid #888;
      padding: 8px;
      font-size: 12px;
      box-shadow: 2px 2px 5px rgba(0,0,0,0.3);
      z-index: 1000;
      max-width: 300px;
    }
    .popup-close {
      cursor: pointer;
      color: #aaa;
      float: right;
    }
  </style>
</head>
<body>
<div id="graph">
  <svg id="svgGraph"></svg>
</div>
<script>
/* Konstanten für Knotenmaße und Abstände */
const nodeW = 120, nodeH = 50;
const verticalSpacing = 300;  // Erheblicher vertikaler Abstand
const horizontalSpacing = 200; // Erheblicher horizontaler Abstand

/* --- Layout-Algorithmus (Reingold–Tilford) --- */
function firstWalk(node, depth) {
  node.y = depth * (nodeH + verticalSpacing);  // vertikaler Abstand pro Ebene
  if (node.children && node.children.length > 0) {
    node.children.forEach(child => firstWalk(child, depth+1));
    let sum = 0;
    node.children.forEach(child => { sum += child.x; });
    node.x = sum / node.children.length;
  } else {
    node.x = firstWalk.currentX;
    firstWalk.currentX += (nodeW + horizontalSpacing);
  }
}
firstWalk.currentX = 0;
function traverse(node, callback) {
  callback(node);
  if(node.children) {
    node.children.forEach(child => traverse(child, callback));
  }
}
function adjustTree(root) {
  let min = Infinity;
  traverse(root, n => { if(n.x < min) min = n.x; });
  if(min < 0) traverse(root, n => { n.x += -min; });
}
function layoutTree(root) {
  firstWalk.currentX = 0;
  firstWalk(root, 0);
  adjustTree(root);
}

/* --- Hilfsfunktionen zur Datenauslese --- */
function extractValue(valObj) {
  if(typeof valObj === "string" || typeof valObj === "number") return valObj.toString();
  if(valObj && valObj.set) return valObj.set.join(", ");
  if(valObj && valObj.prefix) return valObj.prefix.addr + "/" + valObj.prefix.len;
  return "*";
}
function extractInterfaceValue(valObj) {
  return (valObj && valObj.set) ? valObj.set.join(", ") : extractValue(valObj);
}
function formatMatchObject(matchObj) {
  var variable = (matchObj.left && matchObj.left.ct && matchObj.left.ct.key) ? matchObj.left.ct.key :
                 (matchObj.left && matchObj.left.meta && matchObj.left.meta.key) ? matchObj.left.meta.key :
                 (matchObj.left && matchObj.left.payload ? (matchObj.left.payload.field || "flags") : "unknown");
  var value = Array.isArray(matchObj.right) ? matchObj.right.join(", ") : extractValue(matchObj.right);
  return variable + "=" + value;
}
function extractRuleDetails(rule) {
  let pkts = 0, bytes = 0, protocol = "all", ifaceIn = "*", ifaceOut = "*";
  let paramsArr = [];
  if(Array.isArray(rule.expr)) {
    rule.expr.forEach(expr => {
      if(expr.counter) { pkts = expr.counter.packets || pkts; bytes = expr.counter.bytes || bytes; }
      if(expr.match) {
        let left = expr.match.left;
        if(left.meta && left.meta.key === "iifname") { ifaceIn = extractInterfaceValue(expr.match.right); return; }
        if(left.meta && left.meta.key === "oifname") { ifaceOut = extractInterfaceValue(expr.match.right); return; }
        if(left.meta && left.meta.key === "l4proto") { protocol = extractValue(expr.match.right); return; }
        if(left.payload && left.payload.field) { paramsArr.push((left.payload.field || "flags") + "=" + extractValue(expr.match.right)); return; }
        paramsArr.push(formatMatchObject(expr.match));
      }
      if(expr.dnat) {
        let dnatAddr = expr.dnat.addr || "*";
        let dnatPort = expr.dnat.port ? extractValue(expr.dnat.port) : "";
        paramsArr.push("dnat=" + dnatAddr + (dnatPort ? ":" + dnatPort : ""));
      }
    });
  }
  let comment = rule.comment || "";
  return { pkts, bytes, protocol, ifaceIn, ifaceOut, params: paramsArr.join(" | "), comment };
}

/* --- Popup-Funktion --- */
function formatPopupContent(d) {
  let html = "<div>";
  html += "<strong>ID:</strong> " + d.id + "<br>";
  html += "<strong>Name:</strong> " + d.label + "<br>";
  if(d.details) {
    if(d.details.hook) html += "<strong>Hook:</strong> " + d.details.hook + "<br>";
    if(d.details.policy) html += "<strong>Policy:</strong> " + d.details.policy + "<br>";
    if(d.details.ifaceIn) html += "<strong>In:</strong> " + d.details.ifaceIn + "<br>";
    if(d.details.ifaceOut) html += "<strong>Out:</strong> " + d.details.ifaceOut + "<br>";
    if(d.details.params) html += "<strong>Params:</strong> " + d.details.params + "<br>";
    if(d.details.comment) html += "<strong>Comment:</strong> " + d.details.comment + "<br>";
  }
  html += "</div>";
  return html;
}
function showPopup(d, event) {
  // Popup wird am Klick geöffnet und verdeckt nicht den Graphen
  let existing = document.getElementById("popup");
  if(existing) existing.parentNode.removeChild(existing);
  let popup = document.createElement("div");
  popup.setAttribute("id", "popup");
  popup.setAttribute("class", "popup");
  popup.style.left = event.pageX + "px";
  popup.style.top = event.pageY + "px";
  popup.innerHTML = '<span class="popup-close" onclick="document.getElementById(\'popup\').remove()">[x]</span>' + formatPopupContent(d);
  document.body.appendChild(popup);
}

/* --- Farbzuweisungen --- */
function getChainColor(nodeData) {
  if(!nodeData.children || nodeData.children.length === 0) {
    if(nodeData.details && nodeData.details.policy && nodeData.details.policy.toLowerCase() === "drop")
      return { fill: "#ffcccc", stroke: "#ff6666" };
    else
      return { fill: "#ccffcc", stroke: "#66ff66" };
  }
  let fill = "#ffffff", stroke = "#ccc";
  if(nodeData.typeGroup === "filter") {
    if(nodeData.hook === "input" || nodeData.hook === "prerouting") { fill = "#e6f7ff"; stroke = "#91d5ff"; }
    else if(nodeData.hook === "output" || nodeData.hook === "postrouting") { fill = "#d6e4ff"; stroke = "#597ef7"; }
    else { fill = "#f0f5ff"; stroke = "#adc6ff"; }
  } else if(nodeData.typeGroup === "nat") {
    if(nodeData.hook === "input" || nodeData.hook === "prerouting") { fill = "#f6ffed"; stroke = "#73d13d"; }
    else if(nodeData.hook === "output" || nodeData.hook === "postrouting") { fill = "#d9f7be"; stroke = "#52c41a"; }
    else { fill = "#eaff8f"; stroke = "#b7eb8f"; }
  } else if(nodeData.typeGroup === "route") {
    if(nodeData.hook === "input" || nodeData.hook === "prerouting") { fill = "#fff1b8"; stroke = "#ffe58f"; }
    else if(nodeData.hook === "output" || nodeData.hook === "postrouting") { fill = "#ffe7ba"; stroke = "#ffa940"; }
    else { fill = "#fffb8f"; stroke = "#ffc069"; }
  }
  return { fill, stroke };
}
function getRuleColor(nodeData) {
  if(nodeData.ruleAction === "block") return { fill: "#ffcccc", stroke: "#ff6666" };
  if(nodeData.ruleAction === "accept") return { fill: "#ccffcc", stroke: "#66ff66" };
  if(nodeData.ruleAction === "mangle") return { fill: "#ffffcc", stroke: "#cccc33" };
  return { fill: "#ccffcc", stroke: "#66ff66" };
}

/* --- Baum-Datenstruktur aus nftData erzeugen --- */
function buildTree(nftData) {
  let chainMap = {};
  nftData.nftables.forEach(item => {
    if(item.chain) {
      let chain = item.chain;
      let id = chain.name.toLowerCase();
      let typeGroup = chain.type ? chain.type.toLowerCase() : "filter";
      let hook = chain.hook ? chain.hook.toLowerCase() : "";
      let zone = "middle";
      if(hook === "input" || hook === "prerouting") zone = "left";
      else if(hook === "output" || hook === "postrouting") zone = "right";
      else if(hook === "forward") zone = "middle";
      chainMap[id] = {
        id: id,
        label: chain.name + (chain.policy ? " (" + chain.policy + ")" : ""),
        type: "chain",
        typeGroup: typeGroup,
        hook: hook,
        zone: zone,
        details: chain,
        children: []
      };
    }
  });
  nftData.nftables.forEach(item => {
    if(item.rule) {
      let rule = item.rule;
      let parentName = rule.chain ? rule.chain.toLowerCase() : null;
      if(!parentName || !chainMap[parentName]) return;
      let ruleAction = "accept";
      if(Array.isArray(rule.expr)) {
        for(let i=0; i<rule.expr.length; i++){
          let expr = rule.expr[i];
          if(expr.mangle) { ruleAction = "mangle"; break; }
          if(expr.drop !== undefined || expr.reject !== undefined) { ruleAction = "block"; break; }
          if(expr.accept !== undefined) { ruleAction = "accept"; break; }
        }
      }
      let details = extractRuleDetails(rule);
      let ruleNode = {
        id: "rule_" + Math.random().toString(36).substr(2,9),
        label: (details.params ? details.params.substring(0,15) : "Rule") + " | " + (details.ifaceIn || "") + "/" + (details.ifaceOut || ""),
        type: "rule",
        ruleAction: ruleAction,
        details: details,
        children: []
      };
      chainMap[parentName].children.push(ruleNode);
      if(Array.isArray(rule.expr)) {
        rule.expr.forEach(expr => {
          if((expr.jump && expr.jump.target) || (expr.goto && expr.goto.target)) {
            let targetName = (expr.jump ? expr.jump.target : expr.goto.target).toLowerCase();
            if(chainMap[targetName]) {
              let targetChain = JSON.parse(JSON.stringify(chainMap[targetName]));
              targetChain.fromRule = true;
              ruleNode.children.push(targetChain);
            }
          }
        });
      }
    }
  });
  let topChains = [];
  Object.keys(chainMap).forEach(key => {
    if(!chainMap[key].fromRule) topChains.push(chainMap[key]);
  });
  return { id: "netfilter_root", label: "Netfilter", type: "root", children: topChains };
}

/* --- Rendering: Layout und Zeichnen des Baumes --- */
function renderTree(root) {
  // Berechne Layout
  layoutTree(root);

  const svg = document.getElementById("svgGraph");
  while(svg.firstChild) { svg.removeChild(svg.firstChild); }

  const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
  g.setAttribute("id", "graphGroup");
  svg.appendChild(g);

  // Arrow Marker definieren
  const defs = document.createElementNS("http://www.w3.org/2000/svg", "defs");
  const marker = document.createElementNS("http://www.w3.org/2000/svg", "marker");
  marker.setAttribute("id", "arrow");
  marker.setAttribute("viewBox", "0 -5 10 10");
  marker.setAttribute("refX", "5");
  marker.setAttribute("refY", "0");
  marker.setAttribute("markerWidth", "5");
  marker.setAttribute("markerHeight", "5");
  marker.setAttribute("orient", "auto");
  const markerPath = document.createElementNS("http://www.w3.org/2000/svg", "path");
  markerPath.setAttribute("d", "M0,-5L10,0L0,5");
  markerPath.setAttribute("fill", "#999");
  marker.appendChild(markerPath);
  defs.appendChild(marker);
  svg.insertBefore(defs, svg.firstChild);

  function drawEdges(node) {
    if(node.children) {
      node.children.forEach(child => {
        const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
        line.setAttribute("x1", node.x + nodeW/2);
        line.setAttribute("y1", node.y + nodeH);
        line.setAttribute("x2", child.x + nodeW/2);
        line.setAttribute("y2", child.y);
        line.setAttribute("stroke", "#999");
        line.setAttribute("stroke-width", "2");
        line.setAttribute("marker-end", "url(#arrow)");
        g.appendChild(line);
        drawEdges(child);
      });
    }
  }
  drawEdges(root);

  function drawNodes(node) {
    const nodeGroup = document.createElementNS("http://www.w3.org/2000/svg", "g");
    nodeGroup.setAttribute("class", "node");
    nodeGroup.setAttribute("transform", "translate(" + node.x + "," + node.y + ")");
    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("width", nodeW);
    rect.setAttribute("height", nodeH);
    rect.setAttribute("rx", 10);
    rect.setAttribute("ry", 10);
    let color = { fill: "#fff", stroke: "#000" };
    if(node.type === "chain") color = getChainColor(node);
    else if(node.type === "rule") color = getRuleColor(node);
    rect.setAttribute("fill", color.fill);
    rect.setAttribute("stroke", color.stroke);
    nodeGroup.appendChild(rect);

    const text = document.createElementNS("http://www.w3.org/2000/svg", "text");
    text.setAttribute("x", 5);
    text.setAttribute("y", 20);
    let info = node.label;
    if(node.details) {
      info += " | " + (node.details.ifaceIn || "") + "/" + (node.details.ifaceOut || "");
      if(node.details.params) info += " | " + node.details.params.substring(0,15);
      if(node.ruleAction === "mangle") info += " | Mangle";
    }
    text.textContent = info;
    nodeGroup.appendChild(text);

    nodeGroup.addEventListener("click", e => {
      e.stopPropagation();
      showPopup(node, e);
    });
    g.appendChild(nodeGroup);
    if(node.children) {
      node.children.forEach(child => drawNodes(child));
    }
  }
  drawNodes(root);
}

/* --- Zoom & Pan --- */
function enableZoomPan(svgElem) {
  let isPanning = false, startX = 0, startY = 0, translateX = 0, translateY = 0, currentScale = 1;
  const g = document.getElementById("graphGroup");
  svgElem.addEventListener("mousedown", function(e) {
    isPanning = true;
    startX = e.clientX;
    startY = e.clientY;
  });
  svgElem.addEventListener("mousemove", function(e) {
    if(!isPanning) return;
    let dx = e.clientX - startX, dy = e.clientY - startY;
    translateX += dx;
    translateY += dy;
    g.setAttribute("transform", "translate(" + translateX + "," + translateY + ") scale(" + currentScale + ")");
    startX = e.clientX;
    startY = e.clientY;
  });
  svgElem.addEventListener("mouseup", function(e) { isPanning = false; });
  svgElem.addEventListener("mouseleave", function(e) { isPanning = false; });
  svgElem.addEventListener("wheel", function(e) {
    e.preventDefault();
    let scaleFactor = e.deltaY < 0 ? 1.1 : 0.9;
    currentScale *= scaleFactor;
    g.setAttribute("transform", "translate(" + translateX + "," + translateY + ") scale(" + currentScale + ")");
  });
}
function setupZoomPan() {
  const svg = document.getElementById("svgGraph");
  enableZoomPan(svg);
}

/* --- Hauptprogramm --- */
fetch("/admin/nft.json")
  .then(response => response.json())
  .then(data => {
    let tree = buildTree(data);
    layoutTree(tree);
    renderTree(tree);
    setupZoomPan();
  })
  .catch(err => {
    document.getElementById("graph").innerHTML = "<p>Fehler beim Laden der Daten: " + err + "</p>";
  });
</script>
</body>
</html>
EOM

. /usr/lib/www/page-post.sh
