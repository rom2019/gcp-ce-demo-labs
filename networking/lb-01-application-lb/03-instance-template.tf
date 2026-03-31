# ────────────────────────────────────────────────────────────────────
# 시작 스크립트: nginx + 쇼핑몰 웹 앱 설치
# ────────────────────────────────────────────────────────────────────
locals {
  startup_script = <<-STARTUP
    #!/bin/bash
    set -e
    export DEBIAN_FRONTEND=noninteractive

    # nginx 설치
    apt-get update -y
    apt-get install -y nginx curl

    # 인스턴스 메타데이터 조회 (로드밸런싱 확인용)
    INSTANCE_NAME=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/name" \
      -H "Metadata-Flavor: Google" || echo "unknown")
    ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" \
      -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}' || echo "unknown")
    INSTANCE_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip" \
      -H "Metadata-Flavor: Google" || echo "unknown")

    # ── 헬스체크 엔드포인트 (/health) ──────────────────────────────
    echo "OK" > /var/www/html/health

    # ── 쇼핑몰 웹 페이지 생성 ──────────────────────────────────────
    cat > /var/www/html/index.html << 'SHOPHTML'
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GCP 쇼핑몰</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Malgun Gothic', 'Apple SD Gothic Neo', Arial, sans-serif; background: #f5f7fa; }

    header {
      background: #4285F4;
      color: white;
      padding: 1rem 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      box-shadow: 0 2px 6px rgba(0,0,0,0.2);
      position: sticky; top: 0; z-index: 100;
    }
    .logo { font-size: 1.6rem; font-weight: bold; letter-spacing: -0.5px; }
    .logo span { color: #FBBC05; }
    nav a { color: rgba(255,255,255,0.9); text-decoration: none; margin-left: 1.5rem; font-size: 0.9rem; }
    nav a:hover { color: white; text-decoration: underline; }

    .hero {
      background: linear-gradient(135deg, #4285F4 0%, #34A853 100%);
      color: white;
      padding: 4rem 2rem;
      text-align: center;
    }
    .hero h2 { font-size: 2.4rem; margin-bottom: 0.8rem; }
    .hero p { font-size: 1.15rem; opacity: 0.9; }
    .hero .btn {
      display: inline-block;
      background: #FBBC05;
      color: #222;
      padding: 0.85rem 2.5rem;
      border-radius: 30px;
      text-decoration: none;
      font-weight: bold;
      margin-top: 1.8rem;
      font-size: 1.05rem;
      box-shadow: 0 4px 12px rgba(0,0,0,0.2);
      transition: transform 0.15s;
    }
    .hero .btn:hover { transform: translateY(-2px); }

    .section { max-width: 1200px; margin: 2.5rem auto; padding: 0 1.5rem; }
    .section-title {
      font-size: 1.6rem;
      margin-bottom: 1.5rem;
      color: #222;
      border-bottom: 3px solid #4285F4;
      padding-bottom: 0.6rem;
    }

    .product-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
      gap: 1.5rem;
    }
    .product-card {
      background: white;
      border-radius: 14px;
      padding: 1.5rem 1.2rem;
      text-align: center;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08);
      transition: transform 0.2s, box-shadow 0.2s;
    }
    .product-card:hover {
      transform: translateY(-5px);
      box-shadow: 0 10px 28px rgba(0,0,0,0.14);
    }
    .product-emoji { font-size: 3.8rem; margin-bottom: 0.8rem; }
    .product-name { font-size: 1rem; font-weight: bold; color: #333; margin-bottom: 0.4rem; }
    .product-rating { color: #FBBC05; font-size: 0.85rem; margin-bottom: 0.6rem; }
    .product-price { color: #EA4335; font-size: 1.25rem; font-weight: bold; margin-bottom: 1rem; }
    .btn-buy {
      background: #4285F4;
      color: white;
      border: none;
      padding: 0.6rem 1.2rem;
      border-radius: 20px;
      cursor: pointer;
      font-size: 0.9rem;
      width: 100%;
      transition: background 0.15s;
    }
    .btn-buy:hover { background: #3367D6; }

    .banner {
      background: linear-gradient(90deg, #EA4335, #FBBC05);
      color: white;
      text-align: center;
      padding: 1.2rem;
      border-radius: 12px;
      margin-bottom: 2rem;
      font-size: 1.1rem;
      font-weight: bold;
    }

    /* 서버 정보 박스 (로드밸런싱 확인용) */
    .server-info {
      background: #1a1a2e;
      color: #00ff88;
      font-family: 'Courier New', Courier, monospace;
      padding: 1.2rem 1.8rem;
      border-radius: 10px;
      font-size: 0.88rem;
      border: 1px solid #00ff8844;
    }
    .server-info h3 { color: #64b5f6; margin-bottom: 0.6rem; font-size: 1rem; }
    .server-info .info-row { margin: 0.3rem 0; }
    .server-info .label { color: #aaa; }
    .server-info .hint {
      color: #666;
      font-size: 0.78rem;
      margin-top: 0.8rem;
      border-top: 1px solid #333;
      padding-top: 0.6rem;
    }

    footer {
      background: #222;
      color: #999;
      text-align: center;
      padding: 2rem 1rem;
      margin-top: 3rem;
    }
    footer a { color: #4285F4; text-decoration: none; }
    footer .sub { font-size: 0.8rem; margin-top: 0.5rem; color: #666; }
  </style>
</head>
<body>

<header>
  <div class="logo">GCP <span>쇼핑몰</span></div>
  <nav>
    <a href="#">홈</a>
    <a href="#">전자제품</a>
    <a href="#">패션</a>
    <a href="#">생활용품</a>
    <a href="#">고객센터</a>
  </nav>
</header>

<div class="hero">
  <h2>&#128717; 특별 할인 세일</h2>
  <p>최대 70% 할인! 오늘만 진행되는 특가 상품을 만나보세요.</p>
  <a href="#products" class="btn">지금 쇼핑하기 &rarr;</a>
</div>

<div class="section" id="products">
  <div class="banner">&#128293; 오늘의 특가! 전 품목 무료배송 &nbsp;|&nbsp; 5만원 이상 구매 시 5% 추가 할인</div>

  <div class="section-title">&#128293; 인기 상품</div>
  <div class="product-grid">

    <div class="product-card">
      <div class="product-emoji">&#128187;</div>
      <div class="product-name">GCP 울트라북 Pro 14</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9733; (4.9 / 리뷰 1,204)</div>
      <div class="product-price">&#8361;1,299,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#128241;</div>
      <div class="product-name">Pixel 스마트폰 X Pro</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9734; (4.7 / 리뷰 892)</div>
      <div class="product-price">&#8361;899,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#127911;</div>
      <div class="product-name">클라우드 무선 이어폰</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9733; (4.8 / 리뷰 2,341)</div>
      <div class="product-price">&#8361;249,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#8987;</div>
      <div class="product-name">스마트워치 Ultra S2</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9734; (4.6 / 리뷰 677)</div>
      <div class="product-price">&#8361;399,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#128247;</div>
      <div class="product-name">미러리스 카메라 4K</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9733; (4.9 / 리뷰 438)</div>
      <div class="product-price">&#8361;1,599,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#128433;</div>
      <div class="product-name">게이밍 마우스 G Pro X</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9734; (4.5 / 리뷰 1,098)</div>
      <div class="product-price">&#8361;89,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#128268;</div>
      <div class="product-name">USB-C 허브 10in1</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9734; (4.4 / 리뷰 3,210)</div>
      <div class="product-price">&#8361;59,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

    <div class="product-card">
      <div class="product-emoji">&#128444;</div>
      <div class="product-name">4K 모니터 32인치 IPS</div>
      <div class="product-rating">&#9733;&#9733;&#9733;&#9733;&#9733; (4.8 / 리뷰 521)</div>
      <div class="product-price">&#8361;699,000</div>
      <button class="btn-buy">장바구니 담기</button>
    </div>

  </div>
</div>

<!-- 서버 정보: 로드밸런싱 확인용 -->
<div class="section">
  <div class="server-info">
    <h3>&#128421; 서버 정보 (Load Balancing 확인)</h3>
    <div class="info-row"><span class="label">인스턴스명 : </span>SERVER_HOSTNAME</div>
    <div class="info-row"><span class="label">Zone      : </span>SERVER_ZONE</div>
    <div class="info-row"><span class="label">내부 IP   : </span>SERVER_IP</div>
    <div class="hint">
      &#128161; 페이지를 새로고침(F5)하면 Application LB가 다른 인스턴스로 요청을 분산합니다.<br>
      인스턴스명이 바뀌는 것을 확인하세요.
    </div>
  </div>
</div>

<footer>
  <p>&copy; 2024 GCP 쇼핑몰 &nbsp;|&nbsp; <a href="#">이용약관</a> &nbsp;|&nbsp; <a href="#">개인정보처리방침</a></p>
  <p class="sub">Google Cloud Platform &mdash; Application Load Balancer 실습 데모</p>
</footer>

</body>
</html>
SHOPHTML

    # 플레이스홀더를 실제 인스턴스 정보로 교체
    sed -i "s/SERVER_HOSTNAME/$INSTANCE_NAME/g" /var/www/html/index.html
    sed -i "s/SERVER_ZONE/$ZONE/g"              /var/www/html/index.html
    sed -i "s/SERVER_IP/$INSTANCE_IP/g"         /var/www/html/index.html

    # nginx 시작
    systemctl enable nginx
    systemctl restart nginx
  STARTUP
}

# ────────────────────────────────────────────────────────────────────
# 인스턴스 템플릿
# ────────────────────────────────────────────────────────────────────
resource "google_compute_instance_template" "shop" {
  name_prefix  = "shop-template-"
  machine_type = "e2-medium"
  region       = var.region

  tags = ["shop-backend"]

  disk {
    source_image = "debian-cloud/debian-12"
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-balanced"
    auto_delete  = true
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
    # access_config 없음 → 외부 IP 미할당 (Cloud NAT로 인터넷 접근)
  }

  metadata = {
    startup-script = local.startup_script
  }

  service_account {
    # 기본 Compute Engine 서비스 계정 사용
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_compute_router_nat.nat]
}
