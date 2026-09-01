from app.intelligence.provider_guard import (
    AIProvider,
    BillingOwner,
    ProviderPolicy,
    evaluate_provider_call,
)


def test_chatgpt_only_blocks_bitey_fallback():
    policy = ProviderPolicy(
        provider=AIProvider.CHATGPT,
        model="chatgpt-free",
        exclusive=True,
        consented=True,
        billing_owner=BillingOwner.USER,
        allow_paid_external=False,
        cost_known=False,
    )
    decision = evaluate_provider_call(policy, fallback_provider=AIProvider.BITEY)
    assert decision.allowed is False


def test_no_provider_is_not_authorized():
    policy = ProviderPolicy(
        provider=AIProvider.OTHER,
        model="unknown",
        consented=False,
        billing_owner=BillingOwner.UNKNOWN,
    )
    assert evaluate_provider_call(policy).allowed is False


def test_paid_external_requires_explicit_consent_and_cost_policy():
    policy = ProviderPolicy(
        provider=AIProvider.CLAUDE,
        model="claude",
        consented=True,
        billing_owner=BillingOwner.USER,
        allow_paid_external=True,
        cost_known=True,
        max_spend_per_operation=1.0,
    )
    assert evaluate_provider_call(policy, estimated_cost=0.5).allowed is True
    assert evaluate_provider_call(policy, estimated_cost=1.5).allowed is False


def test_background_external_ai_is_off_by_default():
    policy = ProviderPolicy(
        provider=AIProvider.CLAUDE,
        model="claude",
        consented=True,
        billing_owner=BillingOwner.USER,
        allow_paid_external=True,
        cost_known=True,
    )
    assert evaluate_provider_call(policy, estimated_cost=0.1, background=True).allowed is False


def test_unknown_external_cost_fails_closed():
    policy = ProviderPolicy(
        provider=AIProvider.OTHER,
        model="external",
        consented=True,
        billing_owner=BillingOwner.USER,
        allow_paid_external=True,
        cost_known=False,
    )
    assert evaluate_provider_call(policy).allowed is False
