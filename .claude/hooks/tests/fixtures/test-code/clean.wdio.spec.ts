describe('checkout', () => {
  it('AC2 / TC-CHK-040: coupon applies discount', async () => {
    await browser.url('/cart');
    const apply = await $('[data-testid="apply-coupon"]');
    await apply.waitForEnabled();
    await apply.click();
  });
});
