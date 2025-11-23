export default {
  async fetch(request, env, ctx) {
    // CORSヘッダーの設定（Flutter Webからのアクセスを許可するために必須）
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*", // 本番環境では特定のドメインに制限することを推奨
      "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    // プリフライトリクエスト（OPTIONS）への対応
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: corsHeaders,
      });
    }

    // 返却するデータ（JSON）
    const data = [
      {
        id: 1,
        title: "Cloudflare Workers",
        description: "エッジネットワークで動作するサーバーレス環境です。",
        icon: "cloud"
      },
      {
        id: 2,
        title: "Flutter Web",
        description: "単一のコードベースからWebアプリを構築できます。",
        icon: "flutter"
      },
      {
        id: 3,
        title: "高速配信",
        description: "世界中のデータセンターから低遅延でレスポンスを返します。",
        icon: "speed"
      }
    ];

    // JSONレスポンスの返却
    return new Response(JSON.stringify(data), {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json;charset=UTF-8",
      },
    });
  },
};
