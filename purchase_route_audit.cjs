// Offline inspection only. No browser, network, GTM write, or live event.
// node purchase_route_audit.cjs gtm-resource.json facebook_pixel.js
// The candidate is a routing MODEL, not an importable GTM container.
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');

function selectedTags(resource, event, sendTo) {
  const macro = n => {
    if (n === 0 || n === 1) return event;
    if (n === 2) return sendTo;
    throw new Error('Unsupported routing macro ' + n);
  };
  const value = x => Array.isArray(x) && x[0] === 'macro' ? macro(x[1]) : x;
  const predicate = n => {
    const p = resource.predicates[n], a = String(value(p.arg0) ?? ''), b = String(value(p.arg1));
    switch (p.function) {
      case '_eq': return a === b;
      case '_cn': return a.includes(b);
      case '_sw': return a.startsWith(b);
      case '_re': return new RegExp(b).test(a);
      default: throw new Error('Unsupported predicate ' + p.function);
    }
  };
  const add = new Set(), block = new Set();
  for (const rule of resource.rules) {
    if (!rule.every(c => c[0] === 'if' ? c.slice(1).every(predicate) :
      c[0] === 'unless' ? c.slice(1).every(n => !predicate(n)) : true)) continue;
    for (const c of rule) {
      if (c[0] === 'add') c.slice(1).forEach(n => add.add(n));
      if (c[0] === 'block') c.slice(1).forEach(n => block.add(n));
    }
  }
  return [...add].filter(n => !block.has(n)).map(n => resource.tags[n].tag_id);
}

function propose(resource) {
  const result = structuredClone(resource);
  const index = result.tags.findIndex(t => t.tag_id === 25);
  assert.notEqual(index, -1, 'Expected tag 25');
  assert.equal(result.tags[index].vtp_optInMetaCAPI, true, 'CAPI opt-in changed; review again');
  const idMacro = result.macros[result.tags[index].vtp_eventId[1]];
  assert.equal(idMacro.function, '__c');
  assert.ok(JSON.stringify(idMacro).includes('macro'), 'Expected per-GTM-event ID');
  result.predicates.push({function: '_eq', arg0: ['macro', 0], arg1: 'purchase'});
  result.rules.push([['if', result.predicates.length - 1], ['block', index]]);
  return result;
}

function audit(resource, nativeSource) {
  let checks = 0;
  const check = (condition, message) => { assert.ok(condition, message); checks++; };
  const before = JSON.stringify(resource), candidate = propose(resource);
  const tags = (r, event, sendTo = 'G-EXAMPLE') => selectedTags(r, event, sendTo);
  check(tags(resource, 'purchase').includes(25), 'Baseline must send GTM Purchase');
  check(!tags(candidate, 'purchase').includes(25), 'Candidate blocks GTM Purchase');
  check(tags(candidate, 'purchase').includes(23), 'GA4 forwarding remains');
  check(tags(candidate, 'gtm.dom').includes(25), 'CAPI opt-in initialization route remains');
  check(tags(candidate, 'view_item').includes(25), 'Other Meta events remain');
  check(!tags(candidate, 'purchase', 'AW-EXAMPLE').includes(23), 'Existing AW block remains');
  check(JSON.stringify(resource) === before, 'Input must remain unchanged');

  // Use the actual downloaded native class definitions with synthetic input.
  // Do not execute installers, page loads, or the surrounding application IIFE.
  const a = nativeSource.indexOf('class CCFacebookPixelClient');
  const b = nativeSource.indexOf('CloudCartApps.FacebookPixel=', a);
  const c = nativeSource.indexOf('class B{', b);
  const d = nativeSource.indexOf('return new B(', c);
  check(a >= 0 && b > a && c > b && d > c, 'Native layout changed; stop for review');
  const calls = [], fbq = (...args) => calls.push(args);
  const context = vm.createContext({window: {ccRoutes: {checkout: 'https://example.invalid/checkout'},
    CCAppsConfig: {fast_order: {active: false}}, fbq_init: true, fbq}, fbq});
  const Client = vm.runInContext(nativeSource.slice(a, b) + '; CCFacebookPixelClient', context, {timeout: 1000});
  const Handler = vm.runInContext(nativeSource.slice(c, d) + '; B', context, {timeout: 1000});
  const client = new Client({capi: false});
  const handler = Object.create(Handler.prototype); handler.pixel = client;
  const order = {id: 'SYNTHETIC-ORDER', status: 'cancel', subType: 'checkout',
    currency: 'EUR', total: 35.8, products: [{product_id: 762, quantity: 1,
      total_price: {price: 3200}, total_price_per_item: {price: 3200}}]};
  handler.checkoutReturnEvent(order);
  check(calls.length === 0, 'Native cancelled return must not send Purchase');
  order.status = 'success'; handler.checkoutReturnEvent(order);
  check(calls.length === 1 && calls[0][1] === 'Purchase', 'Native success sends Purchase');
  const nativeId = calls[0][3].eventID;
  check(nativeId === crypto.createHash('md5').update('SYNTHETIC-ORDER_762').digest('hex'),
    'Native ID must be derived from order and parent products');
  handler.checkoutReturnEvent(order);
  check(calls.length === 1, 'Native instance rejects repeated same ID');
  check(calls[0][2].value === 35.8 && calls[0][2].currency === 'EUR', 'Native value/currency remain');
  check(!nativeId.includes('50d9cde7-6b51-4be8-86ac-5e3bd01f9e94_'), 'GTM event ID is a different namespace');
  return {mode: 'OFFLINE_ROUTING_MODEL', checks_passed: checks,
    native_cancelled_return_sends_purchase: false, baseline_gtm_purchase_enabled: true,
    candidate_gtm_purchase_enabled: false, candidate_keeps_gtm_dom_meta_initialization: true,
    ready_for_publish: false, live_browser_server_dedup_verified: false,
    limitation: 'Preserved initialization route does not prove CAPI receives native Purchase. Validate timing and one existing real order before publishing.',
    source_sha256: {resource: crypto.createHash('sha256').update(before).digest('hex'),
      native: crypto.createHash('sha256').update(nativeSource).digest('hex')}};
}

if (require.main === module) {
  if (process.argv.length !== 4) throw new Error('Pass gtm-resource.json and facebook_pixel.js snapshots');
  console.log(JSON.stringify(audit(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')),
    fs.readFileSync(process.argv[3], 'utf8')), null, 2));
}
module.exports = {selectedTags, propose, audit};
