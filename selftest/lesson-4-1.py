# Самопроверка проверок 4.1 на копии эталона. Живой платы не требует.
# Запуск из ant-es: python3 es-test/selftest/lesson-4-1.py
# Нужны логи трёх заданий в es-student/411-peripheral-link и компилятор cc.
from pathlib import Path
import shutil,subprocess,os,re,tempfile
root=Path(__file__).resolve().parents[2]; work=Path(tempfile.mkdtemp(prefix='lesson-4-1-negative-')); repo=work/'student';p=repo/'411-peripheral-link'
shutil.copytree(root/'es-student/411-peripheral-link',p,ignore=shutil.ignore_patterns('build'))
(repo/'libs').mkdir()
env=dict(os.environ);env.pop('PICO_SDK_PATH',None);env.pop('CHECKS_JSON',None)
def run(task):
 done=subprocess.run([str(root/f'es-test/checks/check-4-1-{task}.sh'),str(repo)],env=env,capture_output=True,text=True)
 if done.returncode not in (0,1):raise AssertionError(done.stderr)
 return done.returncode==0,done.stdout
cases=0
for k in (1,2,3):
 ok,out=run(k);assert ok,out
 # Все пробельные разделители в транспортных строках могут стать табуляцией.
 f=p/f'device-4-1-{k}.log';old=f.read_text();f.write_text('\n'.join(re.sub(' +','\t',s) if '-->' in s or '<--' in s else s for s in old.splitlines())+'\n')
 ok,out=run(k)
 assert ok, ('WHITESPACE FAILED',k,out)
 f.write_text(old)
def mutate(k,file,change):
 global cases
 f=p/file;old=f.read_text();new=change(old);assert new!=old,file;f.write_text(new)
 try:
  ok,out=run(k);assert not ok,(file,out)
 finally:f.write_text(old)
 cases+=1
for k,token in [(1,'spi_set_slave'),(1,'spi_is_readable'),(1,'time_reached'),(2,'I2C_SLAVE_RECEIVE'),(2,'I2C_SLAVE_REQUEST'),(2,'I2C_SLAVE_FINISH'),(2,'i2c_slave_init'),(2,'i2c_read_byte_raw'),(2,'i2c_write_byte_raw'),(3,'i2c_read_timeout_us'),(3,'i2c_write_timeout_us')]:
 file='platform/spi-link.c' if k==1 else 'platform/i2c-link.c'
 mutate(k,file,lambda t,token=token:t.replace(token,'MISSING')+'\n// '+token+'(i2c1, true);\n')
for k in (1,2,3):
 file=f'device-4-1-{k}.log'
 mutate(k,file,lambda t:t.replace('устройство: 2e8a:000a','устройство: dead:beef'))
 mutate(k,file,lambda t:t.replace('--> uptime','--> missing_uptime'))
mutate(1,'device-4-1-1.log',lambda t:t.replace('spi: hello bytes 5 match yes','spi: hello bytes 4 match yes'))
mutate(1,'device-4-1-1.log',lambda t:t.replace('spi: Pico bytes 4 match yes','spi: Pico bytes 4 match no'))
mutate(2,'device-4-1-2.log',lambda t:t.replace('value 0x37','value 0x00'))
mutate(2,'device-4-1-2.log',lambda t:t.replace('value 0xc8','value 0x37'))
mutate(2,'device-4-1-2.log',lambda t:t.replace('value 0xa5','value 0x00'))
mutate(2,'device-4-1-2.log',lambda t:t.replace('value 0xff','value 0x00'))
mutate(3,'device-4-1-3.log',lambda t:t.replace('value 0x60','value 0x58'))
# Удаление ответа не должно сдвинуть соответствие следующих команд.
mutate(3,'device-4-1-3.log',lambda t:re.sub(r'^.*<-- i2c:.*\n','',t,count=1,flags=re.M))
# Запоздалый ответ и старое значение при ошибке должны отклоняться.
mutate(3,'device-4-1-3.log',lambda t:re.sub(r'^\s*[0-9.]+(?= <-- i2c:)', '9999.000',t,count=1,flags=re.M))
mutate(3,'device-4-1-3.log',lambda t:re.sub(r'^(.*)<-- error: i2c transfer$',r'\1<-- error: i2c transfer\n\1<-- i2c: addr 0x76 reg 0xd0 value 0x60',t,count=1,flags=re.M))
# Постоянные регистры и сохранение выбранного номера проверяются исполняемым тестом.
f=p/'platform/register-bank.c';old=f.read_text()
for modified in [old.replace('return 0xa5','return 0'),old.replace('bank->config = byte','bank->config = 0'),re.sub(r'(void register_bank_finish\([^)]*\)\s*\{)', r'\1\n    bank->selected = REG_ID;', old)]:
 f.write_text(modified)
 exe=work/'registers'
 subprocess.run(['cc','-I',str(p),str(root/'es-test/selftest/register-bank.c'),str(f),'-o',str(exe)],check=True,capture_output=True)
 done=subprocess.run([str(exe)],capture_output=True)
 assert done.returncode!=0,'unit test missed mutation'
 cases+=1
f.write_text(old)
print('Отрицательных вариантов обнаружено',cases)
print('Временная копия',work)
