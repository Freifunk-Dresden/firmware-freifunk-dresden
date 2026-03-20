#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Infos: Firewall"
. /usr/lib/www/page-pre.sh ${0%/*}

cat <<EOM
<h2>${TITLE}</h2>
<br>
EOM

cat <<'EOM'
<!-- Navigation: Gruppiert nach Chain-Typen -->
<div id="navigation">
  <p>Lade Navigation…</p>
</div>

<!-- Inhalt: Hier werden die Fieldsets der einzelnen Chains angezeigt -->
<div id="content">
  <p>Lade Firewall Daten…</p>
</div>

<script>
  // -----------------------------
  // Hilfsfunktionen
  // -----------------------------
  const formatBytes = bytes => {
    if (bytes === 0) return '0 Byte';
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return Math.round(bytes / Math.pow(1024, i)) + ' ' + sizes[i];
  };

  // Standardextraktion: Handhabt Strings, Zahlen, Arrays (set) und prefix-Objekte.
  const extractValue = valObj =>
    typeof valObj === 'string' ? valObj :
    typeof valObj === 'number' ? valObj.toString() :
    valObj && valObj.set ? valObj.set.join(', ') :
    valObj && valObj.prefix ? valObj.prefix.addr + '/' + valObj.prefix.len :
    '*';

  // Für "In" und "Out": Falls mehrere Interfaces (über "set") vorhanden sind,
  // werden diese zeilenweise (mit <br>) dargestellt.
  const extractInterfaceValue = valObj =>
    (valObj && valObj.set) ? valObj.set.join('<br>') : extractValue(valObj);

  // Formatiert ein Match-Objekt im Format "variable=value".
  // Hier werden Versuche unternommen, den Schlüssel aus ct, meta oder payload zu ermitteln.
  // Falls im Payload-Bereich kein field vorhanden ist, wird "flags" verwendet.
  // Wenn bisher "unknown" herauskommt und der Wert "sync" ist, wird "flags" gesetzt.
  const formatMatchObject = matchObj => {
    let variable = matchObj.left && matchObj.left.ct && matchObj.left.ct.key ? matchObj.left.ct.key :
                   matchObj.left && matchObj.left.meta && matchObj.left.meta.key ? (matchObj.left.meta.key.toLowerCase() === "state" ? "state" : matchObj.left.meta.key) :
                   matchObj.left && matchObj.left.payload ? (matchObj.left.payload.field || "flags") :
                   "unknown";
    let value = Array.isArray(matchObj.right) ? matchObj.right.join(', ') : extractValue(matchObj.right);
    if (variable === "unknown") variable = "flags";
    return variable + "=" + value;
  };

  // Neue Funktion: Formatiert ein beliebiges Objekt (z. B. für mangle).
  // Falls das Objekt eine "name"-Eigenschaft enthält, wird diese Basis verwendet.
  // Weitere Schlüssel (außer "name") werden alphabetisch sortiert und mit Punkten angehängt.
  // Dabei werden alle Leerzeichen in Schlüsseln durch Unterstriche ersetzt.
  const formatGeneric = obj => {
    if (obj && typeof obj === 'object' && !Array.isArray(obj) && obj.name) {
      const keys = Object.keys(obj)
                         .filter(k => k !== "name")
                         .map(k => k.replace(/ /g, "_"))
                         .sort();
      return obj.name.replace(/ /g, "_") + (keys.length ? "." + keys.join(".") : "");
    }
    return extractValue(obj);
  };

  // Formatiert ein mangle-Objekt im Format "variable=value".
  // Für den linken Teil (key) und für den rechten Teil (value) wird jeweils formatGeneric genutzt.
  // Außerdem werden alle Leerzeichen in Property-Namen durch Unterstriche ersetzt.
  // Im Value-Bereich: Falls das Unterobjekt einen "key" besitzt, wird dessen Wert ausgegeben.
  const formatMangle = mangleObj => {
    let leftStr = (mangleObj.key && typeof mangleObj.key === 'object') ?
      Object.keys(mangleObj.key)
            .map(prop => prop.replace(/ /g, "_") + "." + formatGeneric(mangleObj.key[prop]))
            .join(";")
      : extractValue(mangleObj.key);
    let rightStr = (mangleObj.value && typeof mangleObj.value === 'object') ?
      Object.keys(mangleObj.value)
            .map(prop => prop.replace(/ /g, "_") + "." +
              ((mangleObj.value[prop] && typeof mangleObj.value[prop] === 'object' && mangleObj.value[prop].key)
                ? mangleObj.value[prop].key : formatGeneric(mangleObj.value[prop])))
            .join(";")
      : extractValue(mangleObj.value);
    return leftStr + "=" + rightStr;
  };

  // -----------------------------
  // Erzeugt ein Fieldset für eine bestimmte Chain.
  // Es wird zunächst – falls in der Chain-Definition vorhanden – die Default Policy ausgegeben,
  // anschließend eine Tabelle mit den Spalten:
  // Pkts, Bytes, Target, Prot, In, Out, Source, Destination, Params, [Mangle,] Comment.
  // Die Spalte "Mangle" wird nur dann angezeigt, wenn wenigstens eine Regel ein mangle-Objekt enthält.
  // Existieren keine Regelobjekte, wird trotzdem eine Tabelle mit einer Hinweiszeile erstellt.
  function generateFirewallTableFiltered(nftJson, chainFilter) {
    // Gruppiere alle Regel-Objekte anhand von rule.chain (in Kleinbuchstaben)
    const rulesByChain = {};
    nftJson.nftables.forEach(item => {
      if (item.rule) {
        const rule = item.rule;
        const cname = (rule.chain || 'unknown').toLowerCase();
        rulesByChain[cname] = rulesByChain[cname] || [];
        rulesByChain[cname].push(rule);
      }
    });
    let html = '';
    if (window.chainDefs && window.chainDefs[chainFilter.toLowerCase()]) {
      let rules = rulesByChain[chainFilter.toLowerCase()] || [];

      // Prüfe, ob in irgendeiner Regel ein mangle-Objekt vorhanden ist:
      let hasMangle = false;
      rules.forEach(function(rule) {
        if (Array.isArray(rule.expr)) {
          rule.expr.forEach(function(expr) {
            if (expr.mangle) {
              hasMangle = true;
            }
          });
        }
      });

      let defaultPolicy = window.chainDefs[chainFilter.toLowerCase()].policy || "";
      html += `<fieldset class="bubble">\n`;
      html += `  <legend>${chainFilter}</legend>\n`;
      if (defaultPolicy) {
        html += `<p>Default Policy: ${defaultPolicy}</p>\n`;
      }
      html += `  <table border="0" cellspacing="0" cellpadding="4">\n`;
      html += `    <thead><tr>\n`;
      html += `      <th>Pkts</th>\n`;
      html += `      <th>Bytes</th>\n`;
      html += `      <th>Target</th>\n`;
      html += `      <th>Prot</th>\n`;
      html += `      <th>In</th>\n`;
      html += `      <th>Out</th>\n`;
      html += `      <th>Source</th>\n`;
      html += `      <th>Destination</th>\n`;
      html += `      <th>Params</th>\n`;
      if (hasMangle) {
        html += `      <th>Mangle</th>\n`;
      }
      html += `      <th>Comment</th>\n`;
      html += `    </tr></thead>\n`;
      html += `    <tbody>\n`;
      if (rules.length === 0) {
        html += `      <tr><td colspan="${hasMangle ? 11 : 10}" style="text-align:center;">Keine Regeln vorhanden</td></tr>\n`;
      } else {
        rules.forEach((rule, index) => {
          let rowClass = (index % 2 === 0) ? "colortoggle1" : "colortoggle2";
          html += `      <tr class="${rowClass}">\n`;
          let pkts = 0, bytes = 0, protocol = 'all', ifaceIn = '*', ifaceOut = '*', source = '*', destination = '*', target = '';
          const paramsArr = [];
          const mangleArr = [];
          if (Array.isArray(rule.expr)) {
            rule.expr.forEach(expr => {
              // Zähler (counter)
              if (expr.counter) {
                pkts = expr.counter.packets || pkts;
                bytes = expr.counter.bytes || bytes;
              }
              if (expr.match) {
                const left = expr.match.left;
                // Interfaces
                if (left.meta && left.meta.key === 'iifname') {
                  ifaceIn = extractInterfaceValue(expr.match.right);
                  return;
                }
                if (left.meta && left.meta.key === 'oifname') {
                  ifaceOut = extractInterfaceValue(expr.match.right);
                  return;
                }
                // Explizite Protokolldefinition (z. B. l4proto)
                if (left.meta && left.meta.key === 'l4proto') {
                  protocol = extractValue(expr.match.right);
                  return;
                }
                // Im payload-Bereich:
                if (left.payload) {
                  if (left.payload.field) {
                    let fieldName = left.payload.field || "flags";
                    paramsArr.push(fieldName + "=" + extractValue(expr.match.right));
                    return;
                  }
                }
                // Alle übrigen Match-Einträge als "variable=value"
                paramsArr.push(formatMatchObject(expr.match));
              }
              // DNAT-Verarbeitung: Falls ein dnat-Objekt vorhanden ist, zeige "dnat=addr:port"
              if (expr.dnat) {
                let dnatAddr = expr.dnat.addr || "*";
                let dnatPort = expr.dnat.port ? extractValue(expr.dnat.port) : "";
                paramsArr.push("dnat=" + dnatAddr + (dnatPort ? ":" + dnatPort : ""));
                return;
              }
              // Erfasse mangle-Ausdrücke und formatiere sie
              if (expr.mangle) {
                mangleArr.push(formatMangle(expr.mangle));
              }
              // Aktionen: jump, accept, drop, reject, masquerade, snat, goto, limit
              if (expr.jump) {
                target = `<a href="#${expr.jump.target}">${expr.jump.target}</a>`;
              } else if (expr.accept !== undefined) {
                if (!target) target = 'ACCEPT';
              } else if (expr.drop !== undefined) {
                if (!target) target = 'DROP';
              } else if (expr.reject !== undefined) {
                if (!target) {
                  target = (typeof expr.reject === 'object' && expr.reject.type) ? 'REJECT (' + expr.reject.type + ')' : 'REJECT';
                }
              } else if (expr.masquerade !== undefined) {
                if (!target) target = 'MASQUERADE';
              } else if (expr.snat !== undefined) {
                if (!target) target = 'SNAT';
              } else if (expr.goto) {
                target = 'GOTO ' + expr.goto.target;
              }
              if (expr.limit) {
                paramsArr.push("limit=" + JSON.stringify(expr.limit));
              }
            });
          }
          if (!target) {
            target = '-';
          }
          const params = paramsArr.join(' | ');
          const mangleStr = mangleArr.join(' | ');
          html += `        <td>${pkts}</td>\n`;
          html += `        <td>${formatBytes(bytes)}</td>\n`;
          html += `        <td>${target}</td>\n`;
          html += `        <td>${protocol}</td>\n`;
          html += `        <td>${ifaceIn}</td>\n`;
          html += `        <td>${ifaceOut}</td>\n`;
          html += `        <td>${source}</td>\n`;
          html += `        <td>${destination}</td>\n`;
          html += `        <td>${params}</td>\n`;
          if (hasMangle) {
            html += `        <td>${mangleStr}</td>\n`;
          }
          html += `        <td>${rule.comment || ''}</td>\n`;
          html += '      </tr>\n';
        });
      }
      html += '    </tbody>\n';
      html += '  </table>\n';
      html += '</fieldset>\n';
    } else {
      html = `<p>Chain "${chainFilter}" nicht gefunden!</p>`;
    }
    return html;
  }

  // -----------------------------
  // Dynamische Navigation:
  // Gruppiere die Chain-Definitionen (aus window.chainDefs) nach ihrem Typ (filter, nat, route).
  // Es werden oben Gruppen-Links (GroupNav) angezeigt. Klickt man auf einen Gruppennamen,
  // erscheint darunter ein Überschrift-Header, und in der Chain-Navigation (ChainNav) werden
  // nur die Chains dieser Gruppe angezeigt. Standardmäßig wird beim leeren Hash die Gruppe "filter" angezeigt.
  function renderNavigation(selectedGroup) {
    let groups = {};
    for (let name in window.chainDefs) {
      let def = window.chainDefs[name];
      if (!def.type) continue;
      let type = def.type.toLowerCase();
      if (type !== "filter" && type !== "nat" && type !== "route") continue;
      groups[type] = groups[type] || [];
      groups[type].push(def);
    }
    selectedGroup = selectedGroup || "filter";

    let navHtml = ""
    navHtml += `<b>JSON-Dump: </b><a href="/admin/nft.json">nft.json</a><br><br>\n`;
		navHtml += "<b>NFT chain types:</b>"
    navHtml += "<ul id='groupNav'>";
    ["filter", "nat", "route"].forEach(function(gr) {
      navHtml += `<li><a href="#group=${gr}" ${gr===selectedGroup ? "style='font-weight:bold'" : ""}>${gr.charAt(0).toUpperCase()+gr.slice(1)}</a></li>`;
    });
    navHtml += "</ul>\n";
    // Überschrift zur aktiven Gruppe
    navHtml += `<h4>Aktive Gruppe: ${selectedGroup.charAt(0).toUpperCase()+selectedGroup.slice(1)}</h4>\n`;
//    navHtml += "<ul id='chainNav'>";
//    if (groups[selectedGroup]) {
//      groups[selectedGroup].forEach(function(def) {
//        navHtml += `<li><a href="#${def.name.toLowerCase()}">${def.name}</a></li>`;
//      });
//    }
//    navHtml += "</ul>";
    document.getElementById("navigation").innerHTML = navHtml;
  }

  // -----------------------------
  // Rendert die Home-Seite für eine ausgewählte Gruppe (z. B. "filter").
  // Es werden nur die Chains dieser Gruppe angezeigt.
  function renderGroupHome(selectedGroup) {
    renderNavigation(selectedGroup);
    const contentDiv = document.getElementById("content");
    let contentHtml = "";
    for (let name in window.chainDefs) {
      let def = window.chainDefs[name];
      if (def.type && def.type.toLowerCase() === selectedGroup) {
        contentHtml += generateFirewallTableFiltered(nftData, def.name.toLowerCase());
      }
    }
    contentDiv.innerHTML = contentHtml;
  }

  // Rendert eine einzelne Chain (Fieldset)
  function renderChain(chainName) {
    let chainDef = window.chainDefs[chainName.toLowerCase()];
    let selectedGroup = (chainDef && chainDef.type) ? chainDef.type.toLowerCase() : "filter";
    renderNavigation(selectedGroup);
    const contentDiv = document.getElementById("content");
    contentDiv.innerHTML = generateFirewallTableFiltered(nftData, chainName.toLowerCase());
  }

  // -----------------------------
  // Routing: Auswertung des Hash.
  // Beginnt der Hash mit "group=", wird die Gruppenansicht (alle Chains dieser Gruppe) gerendert,
  // andernfalls wird angenommen, dass ein einzelner Chain-Name übergeben wurde.
  function handleHashChange() {
    let hash = window.location.hash.substring(1); // Entferne führendes "#"
    if (!hash) {
      window.location.hash = "group=filter";
      return;
    }
    if (hash.indexOf("group=") === 0) {
      let group = hash.split("=")[1].toLowerCase();
      renderGroupHome(group);
    } else {
      renderChain(hash);
    }
  }

  // -----------------------------
  // JSON laden, Chain-Definitionen extrahieren und Seiten-Rendering starten.
  let nftData = null;
  window.addEventListener("hashchange", handleHashChange);
  window.addEventListener("load", function(){
    const jsonUrl = "/admin/nft.json";
    fetch(jsonUrl)
      .then(response => response.json())
      .then(data => {
        nftData = data;
        // Extrahiere alle Chain-Definitionen (Objekte mit "chain")
        let chainArray = [];
        if (nftData.nftables && Array.isArray(nftData.nftables)) {
          chainArray = nftData.nftables;
        } else if (nftData.nxtables && Array.isArray(nftData.nxtables)) {
          chainArray = nftData.nxtables;
        }
        chainArray.forEach(item => {
          if (item.chain) {
            window.chainDefs = window.chainDefs || {};
            let ch = item.chain;
            if(ch.name) {
              window.chainDefs[ch.name.toLowerCase()] = ch;
            }
          }
        });
        // Standardmäßig wird die Gruppe "filter" angezeigt.
        renderNavigation("filter");
        handleHashChange();
      })
      .catch(err => {
        document.getElementById("content").innerHTML = `<p>Fehler beim Laden der Daten: ${err}</p>`;
      });
  });
</script>
EOM

. /usr/lib/www/page-post.sh
