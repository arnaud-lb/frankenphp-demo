import http from 'k6/http';
import { check, sleep } from 'k6';
import { htmlReport } from "https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js";

export default function () {
  const res = http.get('https://localhost');
  check(res, {
  'is status 200': (r) => r.status === 200,
  'verify homepage text': (r) =>
      String(r.body).includes('Hello HomepageController'),
  'protocol is HTTP/2': (r) => r.proto === 'HTTP/2.0',
  });

  const res2 = http.get('https://localhost/api');
  check(res2, {
  'is status 200': (r) => r.status === 200,
  'verify homepage text': (r) =>
      String(r.body).includes('Hello API Platform'),
  'protocol is HTTP/2': (r) => r.proto === 'HTTP/2.0',
  });

  const res3 = http.get('https://localhost/api/monsters.jsonld');
  check(res3, {
  'is status 200': (r) => r.status === 200,
  'verify homepage text': (r) =>
      String(r.body).includes('hydra:Collection'),
  'protocol is HTTP/2': (r) => r.proto === 'HTTP/2.0',
  });
}

export function handleSummary(data) {
  return {
    "summary.html": htmlReport(data),
  };
}

