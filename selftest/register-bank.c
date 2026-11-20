// Проверяет правила созданного ведомого независимо от аппаратного контроллера.
#include <assert.h>
#include "platform/register-bank.h"

int main(void)
{
    register_bank_t bank;
    register_bank_init(&bank);
    assert(register_bank_request(&bank) == 0xa5);
    register_bank_receive(&bank, REG_CONFIG);
    register_bank_receive(&bank, 0x37);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0x37);
    register_bank_receive(&bank, REG_VERSION);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0x01);
    register_bank_receive(&bank, REG_ID);
    register_bank_receive(&bank, 0);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0xa5);
    register_bank_receive(&bank, REG_VERSION);
    register_bank_receive(&bank, 0);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0x01);
    register_bank_receive(&bank, 0xfe);
    register_bank_receive(&bank, 0x55);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0xff);
    register_bank_receive(&bank, REG_CONFIG);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0x37);
    register_bank_receive(&bank, REG_CONFIG);
    register_bank_receive(&bank, 0xc8);
    register_bank_finish(&bank);
    assert(register_bank_request(&bank) == 0xc8);
    register_bank_init(&bank);
    register_bank_receive(&bank, REG_CONFIG);
    assert(register_bank_request(&bank) == 0);
}
