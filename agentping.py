#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import socket
import ssl
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Iterable
from urllib.error import URLError
from urllib.request import Request, urlopen


DEFAULT_TARGETS = {
    "OpenAI": "api.openai.com",
    "Anthropic": "api.anthropic.com",
}

GREEN_MS = 500
YELLOW_MS = 1500


COUNTRY_NAMES = {
    "CN": "中国大陆",
    "HK": "香港",
    "JP": "日本",
    "SG": "新加坡",
    "US": "美国",
    "TW": "台湾",
    "KR": "韩国",
    "GB": "英国",
    "DE": "德国",
    "NL": "荷兰",
}


@dataclass
class CheckResult:
    name: str
    host: str
    status: str
    reason: str
    suggestion: str
    dns_ms: float | None = None
    tcp_ms: float | None = None
    tls_ms: float | None = None
    resolved_ip: str | None = None

    @property
    def total_ms(self) -> float | None:
        parts = [self.dns_ms, self.tcp_ms, self.tls_ms]
        if any(part is None for part in parts):
            return None
        return sum(part for part in parts if part is not None)

    def to_json(self) -> dict[str, object]:
        return {
            "name": self.name,
            "host": self.host,
            "status": self.status,
            "statusLabel": status_label(self.status),
            "reason": self.reason,
            "suggestion": self.suggestion,
            "dnsMs": self.dns_ms,
            "tcpMs": self.tcp_ms,
            "tlsMs": self.tls_ms,
            "totalMs": self.total_ms,
            "resolvedIp": self.resolved_ip,
        }


@dataclass
class AgentStatus:
    name: str
    status: str
    summary: str
    suggestion: str

    def to_json(self) -> dict[str, object]:
        return {
            "name": self.name,
            "status": self.status,
            "statusLabel": status_label(self.status),
            "summary": self.summary,
            "suggestion": self.suggestion,
        }


@dataclass
class Decision:
    status: str
    title: str
    detail: str
    action: str

    def to_json(self) -> dict[str, object]:
        return {
            "status": self.status,
            "statusLabel": status_label(self.status),
            "title": self.title,
            "detail": self.detail,
            "action": self.action,
        }


@dataclass
class EgressInfo:
    status: str
    label: str
    masked_ip: str | None
    network_type: str
    source: str | None = None
    reason: str | None = None

    def to_json(self) -> dict[str, object]:
        return {
            "status": self.status,
            "label": self.label,
            "maskedIp": self.masked_ip,
            "networkType": self.network_type,
            "source": self.source,
            "reason": self.reason,
        }


def elapsed_ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000


def resolve_host(host: str, port: int, timeout: float) -> tuple[list[tuple], float, str | None]:
    socket.setdefaulttimeout(timeout)
    start = time.perf_counter()
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    dns_ms = elapsed_ms(start)
    ip = infos[0][4][0] if infos else None
    return infos, dns_ms, ip


def connect_tcp(addr: tuple, timeout: float) -> tuple[socket.socket, float]:
    start = time.perf_counter()
    sock = socket.create_connection(addr, timeout=timeout)
    return sock, elapsed_ms(start)


def handshake_tls(sock: socket.socket, host: str, timeout: float) -> tuple[ssl.SSLSocket, float]:
    context = ssl.create_default_context()
    sock.settimeout(timeout)
    start = time.perf_counter()
    tls_sock = context.wrap_socket(sock, server_hostname=host)
    return tls_sock, elapsed_ms(start)


def classify_ok(total_ms: float) -> tuple[str, str, str]:
    if total_ms <= GREEN_MS:
        return "green", "链路可用，延迟正常。", "可以正常使用 Agent。"
    if total_ms <= YELLOW_MS:
        return "yellow", "链路可用，但延迟偏高。", "可以使用，但如果 Agent 变慢，建议切换到更稳定的节点。"
    return "yellow", "链路可用，但延迟很高。", "建议切换节点后再运行长任务。"


def check_target(name: str, host: str, port: int, timeout: float) -> CheckResult:
    try:
        infos, dns_ms, resolved_ip = resolve_host(host, port, timeout)
    except socket.gaierror:
        return CheckResult(
            name=name,
            host=host,
            status="red",
            reason="DNS 解析失败，当前网络或代理没有正确找到目标地址。",
            suggestion="先检查本地网络和代理分流规则，再重试。",
        )
    except TimeoutError:
        return CheckResult(
            name=name,
            host=host,
            status="red",
            reason="DNS 解析超时，当前网络解析很不稳定。",
            suggestion="切换节点或 DNS 后再重试。",
        )
    except OSError as error:
        return CheckResult(
            name=name,
            host=host,
            status="red",
            reason=f"DNS 检查失败：{error}",
            suggestion="先确认电脑能正常联网，再检查代理客户端。",
        )

    last_error: Exception | None = None
    for info in infos:
        addr = info[4]
        sock: socket.socket | None = None
        tls_sock: ssl.SSLSocket | None = None
        try:
            sock, tcp_ms = connect_tcp(addr, timeout)
            tls_sock, tls_ms = handshake_tls(sock, host, timeout)
            total_ms = dns_ms + tcp_ms + tls_ms
            status, reason, suggestion = classify_ok(total_ms)
            return CheckResult(
                name=name,
                host=host,
                status=status,
                reason=reason,
                suggestion=suggestion,
                dns_ms=dns_ms,
                tcp_ms=tcp_ms,
                tls_ms=tls_ms,
                resolved_ip=resolved_ip,
            )
        except TimeoutError as error:
            last_error = error
        except ssl.SSLError as error:
            return CheckResult(
                name=name,
                host=host,
                status="red",
                reason="TLS 握手失败，可能是代理拦截、证书异常，或出口链路被干扰。",
                suggestion="先切换节点；如果仍然失败，再检查代理客户端是否开启了 HTTPS 解密。",
                dns_ms=dns_ms,
                resolved_ip=resolved_ip,
            )
        except OSError as error:
            last_error = error
        finally:
            if tls_sock is not None:
                tls_sock.close()
            elif sock is not None:
                sock.close()

    return CheckResult(
        name=name,
        host=host,
        status="red",
        reason=f"无法建立连接：{last_error}" if last_error else "无法建立连接。",
        suggestion="更可能是当前出口节点不可用、被拦截，或代理没有接管这条请求。",
        dns_ms=dns_ms,
        resolved_ip=resolved_ip,
    )


def status_label(status: str) -> str:
    labels = {
        "green": "绿",
        "yellow": "黄",
        "red": "红",
        "gray": "灰",
    }
    return labels.get(status, status)


def format_ms(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.0f}ms"


def parse_targets(values: Iterable[str]) -> dict[str, str]:
    targets = dict(DEFAULT_TARGETS)
    for value in values:
        if "=" not in value:
            raise SystemExit(f"目标格式错误：{value}，请使用 名称=域名")
        name, host = value.split("=", 1)
        name = name.strip()
        host = host.strip()
        if not name or not host:
            raise SystemExit(f"目标格式错误：{value}，请使用 名称=域名")
        targets[name] = host
    return targets


def detect_proxy_env() -> list[str]:
    names = ["HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "https_proxy", "http_proxy", "all_proxy"]
    return [name for name in names if os.environ.get(name)]


def country_label(code: str | None, fallback: str | None) -> str:
    if code:
        return COUNTRY_NAMES.get(code.upper(), code.upper())
    return fallback or "未知地区"


def mask_ip(ip: str | None) -> str | None:
    if not ip:
        return None
    if ":" in ip:
        parts = ip.split(":")
        if len(parts) <= 2:
            return ip
        return ":".join(parts[:2] + ["***"])
    parts = ip.split(".")
    if len(parts) != 4:
        return ip
    return f"{parts[0]}.***.{parts[2]}.{parts[3]}"


def detect_egress_region(timeout: float, proxy_env: list[str]) -> EgressInfo:
    network_type = "代理出口或客户端分流" if proxy_env else "直连或客户端分流"
    endpoints = [
        ("ipapi", "https://ipapi.co/json/"),
        ("ipinfo", "https://ipinfo.io/json"),
    ]

    for source, url in endpoints:
        try:
            request = Request(url, headers={"User-Agent": "AgentPing/0.1"})
            with urlopen(request, timeout=timeout) as response:
                data = json.loads(response.read().decode("utf-8"))
        except (OSError, TimeoutError, URLError, json.JSONDecodeError):
            continue

        ip = data.get("ip")
        city = data.get("city")
        region = data.get("region")
        country = country_label(data.get("country_code") or data.get("country"), data.get("country_name"))
        parts = [part for part in [country, city or region] if part]
        label = " / ".join(parts) if parts else "已检测到出口"
        return EgressInfo(
            status="green",
            label=label,
            masked_ip=mask_ip(ip),
            network_type=network_type,
            source=source,
        )

    return EgressInfo(
        status="yellow",
        label="未能检测出口地区",
        masked_ip=None,
        network_type=network_type,
        reason="地区接口暂时不可用，不影响 API 链路判断。",
    )


def result_by_name(results: list[CheckResult], name: str) -> CheckResult | None:
    for result in results:
        if result.name.lower() == name.lower():
            return result
    return None


def agent_summary(status: str, green: str, yellow: str, red: str) -> str:
    if status == "green":
        return green
    if status == "yellow":
        return yellow
    return red


def build_agent_statuses(results: list[CheckResult], proxy_env: list[str]) -> list[AgentStatus]:
    openai = result_by_name(results, "OpenAI")
    anthropic = result_by_name(results, "Anthropic")

    openai_status = openai.status if openai else "red"
    anthropic_status = anthropic.status if anthropic else "red"

    if openai_status == "red" and anthropic_status == "red":
        cursor_status = "red"
        cursor_summary = "多数模型都不适合继续"
        cursor_suggestion = "先检查本地网络和代理，再重新打开 Cursor。"
    elif openai_status == "red" or anthropic_status == "red":
        cursor_status = "yellow"
        cursor_summary = "看你当前使用的模型"
        cursor_suggestion = "如果当前模型对应红色链路，先换节点或换模型。"
    elif openai_status == "yellow" or anthropic_status == "yellow":
        cursor_status = "yellow"
        cursor_summary = "短任务可用，长任务谨慎"
        cursor_suggestion = "长任务开始前建议切换到更稳定节点。"
    else:
        cursor_status = "green"
        cursor_summary = "可继续使用"
        cursor_suggestion = "OpenAI 和 Anthropic 链路都可用。"

    proxy_status = "green" if proxy_env else "gray"
    proxy_summary = "检测到代理环境变量" if proxy_env else "未检测到代理环境变量"
    proxy_suggestion = "终端请求大概率会走代理。" if proxy_env else "如果依赖客户端分流，请以实际链路结果为准。"

    return [
        AgentStatus(
            name="Codex",
            status=openai_status,
            summary=agent_summary(openai_status, "可以继续", "长任务谨慎", "先暂停"),
            suggestion=openai.suggestion if openai else "OpenAI 链路没有检查结果。",
        ),
        AgentStatus(
            name="Claude Code",
            status=anthropic_status,
            summary=agent_summary(anthropic_status, "可以继续", "长任务谨慎", "先暂停"),
            suggestion=anthropic.suggestion if anthropic else "Anthropic 链路没有检查结果。",
        ),
        AgentStatus(
            name="Cursor",
            status=cursor_status,
            summary=cursor_summary,
            suggestion=cursor_suggestion,
        ),
        AgentStatus(
            name="本地代理",
            status=proxy_status,
            summary=proxy_summary,
            suggestion=proxy_suggestion,
        ),
    ]


def build_decision(results: list[CheckResult], agents: list[AgentStatus]) -> Decision:
    openai = result_by_name(results, "OpenAI")
    anthropic = result_by_name(results, "Anthropic")
    openai_status = openai.status if openai else "red"
    anthropic_status = anthropic.status if anthropic else "red"

    if openai_status == "red" and anthropic_status == "red":
        return Decision(
            status="red",
            title="先别继续跑",
            detail="OpenAI 和 Anthropic 链路都不可用，更像是本地网络或代理没有生效。",
            action="先检查代理客户端和分流规则，再重新检查。",
        )
    if anthropic_status == "red":
        return Decision(
            status="red",
            title="Claude 先暂停",
            detail="Anthropic 链路不可用，Claude Code 很可能是在等网络返回。",
            action="先换 Claude 可用节点，再重新运行任务。",
        )
    if openai_status == "red":
        return Decision(
            status="red",
            title="Codex 先暂停",
            detail="OpenAI 链路不可用，Codex 当前不适合继续跑长任务。",
            action="先换 OpenAI 可用节点，或检查终端代理是否生效。",
        )
    if any(result.status == "yellow" for result in results):
        return Decision(
            status="yellow",
            title="短任务可跑，长任务谨慎",
            detail="核心链路可用，但存在延迟偏高或不稳定。",
            action="如果要跑长任务，建议先换到更稳定节点。",
        )
    return Decision(
        status="green",
        title="可以继续跑 Agent",
        detail="OpenAI 和 Anthropic 链路都可用，当前网络适合继续使用。",
        action="可以开始或继续 Codex、Claude Code、Cursor 任务。",
    )


def build_report(
    results: list[CheckResult],
    agents: list[AgentStatus],
    decision: Decision,
    egress: EgressInfo,
    proxy_env: list[str],
) -> str:
    lines = [
        "Ageng网络医生 诊断报告",
        "",
        f"检查时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"当前出口：{egress.label}" + (f"（{egress.masked_ip}）" if egress.masked_ip else ""),
        f"网络类型：{egress.network_type}",
        "",
        "软件状态：",
    ]
    for agent in agents:
        lines.append(f"- {agent.name}：{status_label(agent.status)}，{agent.summary}")

    lines.extend(["", "链路明细："])
    for result in results:
        lines.append(f"- {result.name}：{status_label(result.status)}，{format_ms(result.total_ms)}，{result.reason}")

    lines.extend(
        [
            "",
            f"本地代理：{', '.join(proxy_env) if proxy_env else '未检测到代理环境变量'}",
            "",
            f"判断：{decision.detail}",
            f"建议：{decision.action}",
        ]
    )
    return "\n".join(lines)


def print_result(result: CheckResult, verbose: bool) -> None:
    total = format_ms(result.total_ms)
    print(f"{result.name}：{status_label(result.status)}  {total}")
    print(f"目标：{result.host}")
    print(f"判断：{result.reason}")
    print(f"建议：{result.suggestion}")
    if verbose:
        print(f"DNS：{format_ms(result.dns_ms)}")
        print(f"TCP：{format_ms(result.tcp_ms)}")
        print(f"TLS：{format_ms(result.tls_ms)}")
        print(f"解析 IP：{result.resolved_ip or '-'}")
    print()


def summarize(results: list[CheckResult]) -> tuple[str, str]:
    if all(result.status == "green" for result in results):
        return "整体正常", "OpenAI 和 Anthropic 链路都可用，可以正常运行 Agent。"
    if any(result.status == "green" for result in results) and any(result.status == "red" for result in results):
        failed = ", ".join(result.name for result in results if result.status == "red")
        return "部分异常", f"{failed} 链路不可用，更像是节点、分流或目标服务侧问题。"
    if all(result.status == "red" for result in results):
        return "整体异常", "所有核心链路都不可用，优先检查本地网络和代理是否生效。"
    return "需要观察", "链路可用但质量一般，长任务前建议换到更稳定的节点。"


def run_check(args: argparse.Namespace) -> int:
    targets = parse_targets(args.target)
    proxy_env = detect_proxy_env()
    results = [check_target(name, host, args.port, args.timeout) for name, host in targets.items()]
    summary, summary_text = summarize(results)
    agents = build_agent_statuses(results, proxy_env)
    decision = build_decision(results, agents)
    egress = detect_egress_region(args.region_timeout, proxy_env) if not args.no_region else EgressInfo(
        status="yellow",
        label="未检测出口地区",
        masked_ip=None,
        network_type="未检测",
        reason="已跳过地区检测。",
    )
    report = build_report(results, agents, decision, egress, proxy_env)

    if args.json:
        payload = {
            "checkedAt": datetime.now().isoformat(timespec="seconds"),
            "summary": summary,
            "summaryText": summary_text,
            "decision": decision.to_json(),
            "agents": [agent.to_json() for agent in agents],
            "egress": egress.to_json(),
            "proxyEnv": proxy_env,
            "results": [result.to_json() for result in results],
            "report": report,
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 1 if any(result.status == "red" for result in results) else 0

    print("Ageng网络医生 诊断结果")
    print()
    print(f"结论：{decision.title}")
    print(decision.detail)
    print(f"建议：{decision.action}")
    print()
    print(f"当前出口：{egress.label}" + (f"（{egress.masked_ip}）" if egress.masked_ip else ""))
    print(f"网络类型：{egress.network_type}")
    print()
    print("软件状态")
    for agent in agents:
        print(f"{agent.name}：{status_label(agent.status)}  {agent.summary}")
    print()
    print("链路明细")
    for result in results:
        print_result(result, args.verbose)

    print(f"总判断：{summary}")
    print(summary_text)
    if proxy_env:
        print(f"检测到代理环境变量：{', '.join(proxy_env)}")
    else:
        print("没有检测到代理环境变量；如果你依赖客户端分流，请以实际链路结果为准。")

    return 1 if any(result.status == "red" for result in results) else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="agentping", description="AI Agent 网络链路诊断工具")
    subparsers = parser.add_subparsers(dest="command")

    check = subparsers.add_parser("check", help="检查 OpenAI 和 Anthropic 链路")
    check.add_argument("--target", action="append", default=[], help="追加检查目标，格式：名称=域名")
    check.add_argument("--timeout", type=float, default=5.0, help="单步超时时间，默认 5 秒")
    check.add_argument("--port", type=int, default=443, help="检查端口，默认 443")
    check.add_argument("--verbose", action="store_true", help="显示 DNS/TCP/TLS 明细")
    check.add_argument("--json", action="store_true", help="输出给菜单栏等程序读取的 JSON")
    check.add_argument("--no-region", action="store_true", help="跳过当前出口地区检测")
    check.add_argument("--region-timeout", type=float, default=2.0, help="出口地区检测超时时间，默认 2 秒")
    check.set_defaults(func=run_check)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
