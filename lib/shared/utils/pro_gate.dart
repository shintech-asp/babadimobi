/// Whether an API error message is the portal's "Pro subscription required"
/// 403 (see `api/v1/portal/_bootstrap.php`'s `portal_require_pro()`) — used
/// across portal screens to show an upgrade prompt instead of a plain error
/// when a Pro-gated action is attempted on a free-tier provider.
bool isProError(String message) => message.toLowerCase().contains('pro subscription');
