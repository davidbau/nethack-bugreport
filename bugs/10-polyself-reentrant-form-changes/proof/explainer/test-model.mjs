// Checks the in-page model (model.js) against the pass/fail matrix that
// run-cbmc.sh expects from CBMC.  Run: node test-model.mjs
await import('./model.js');
const M = globalThis.PolyModel;
let bad = 0;
const E=[
['immediate light bookkeeping','light',{},1],
['legacy delete-before-create','delayedLight',{},0],
['polymon epoch','polymon',{mode:2},1],
['break_armor epoch','break_armor',{mode:2},1],
['polymon identity no-ABA','polymon',{mode:1,allowSame:false},1],
['break_armor identity no-ABA','break_armor',{mode:1,allowSame:false},1],
['polymon identity ABA','polymon',{mode:1},0],
['break_armor identity ABA','break_armor',{mode:1},0],
['polytrap identity','polytrap',{mode:1},0],
['polytrap epoch','polytrap',{mode:2},1],
...[0,1,2,3,4].map(b=>['polymon omit '+b,'polymon',{mode:1,allowSame:false,force:b,omit:b},0]),
...[5,6,7].map(b=>['break_armor omit '+b,'break_armor',{mode:1,allowSame:false,force:b,omit:b},0]),
];
for(const [n,f,o,exp] of E){const v=M.verdict(f,o);if(v.pass!=!!exp)bad++;console.log((v.pass==!!exp?'OK  ':'BAD ')+n,v.pass?'pass':'FAIL: '+v.counterexample.result.failed+' '+JSON.stringify(v.counterexample.choices),'paths',v.paths);}
for (const m of [0,1,2]) {const l=M.exploreAll('polymon',{mode:m}); console.log('mode',m,'leaves',l.length,'fail',l.filter(x=>x.result.failed).length);}

if (bad) { console.error(bad + ' result(s) differ from run-cbmc.sh'); process.exit(1); }
console.log('all ' + E.length + ' results match run-cbmc.sh');
