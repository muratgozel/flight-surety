import './main.css';
import config from './config.json';
import Contract from "./contract.js";

const context = new Map();

(async () => {
  const contract = new Contract({config: config.localhost})
  await contract.init()

  context.set('contract', contract)

  startOperationalStatusChecker()
  onRegisterAirline()
  populateDepartureTime()
  onRegisterFlight()
  onSubmitToOracles()
  onBuyInsurance()
  onWithdraw()
})();

function onWithdraw() {
  const selectBox = document.getElementById('from')
  selectBox.innerHTML = context.get('contract').passengers
    .map((addr, i) => `<option value="${addr}">${(i+1)}. ${addr.toString().slice(0, 12)}...</option>`)
    .join('')

  document.getElementById('withdraw').addEventListener('click', async function (e) {
    e.preventDefault()
    const form = document.forms['withdraw']
    const formData = new FormData(form)
    const result = await context.get('contract').withdraw(formData.get('passenger'))
    form.querySelector('.result-msg').innerText = result instanceof Error ? result.message : 'Withdraw successful.'
  })
}

function onBuyInsurance() {
  const selectBox = document.getElementById('passenger')
  selectBox.innerHTML = context.get('contract').passengers
    .map((addr, i) => `<option value="${addr}">${(i+1)}. ${addr.toString().slice(0, 12)}...</option>`)
    .join('')
  const selectBoxFlights = document.getElementById('flights')
  selectBoxFlights.innerHTML = context.get('contract').flights
    .map((code, i) => `<option value="${code}">${code}</option>`)
    .join('')

  document.getElementById('buy-insurance').addEventListener('click', async function (e) {
    e.preventDefault()
    const form = document.forms['buy-insurance']
    const formData = new FormData(form)
    const code = formData.get('code').toUpperCase()
    const amount = parseFloat(formData.get('amount').trim().split(' ')[0])
    const result = await context.get('contract').buyInsurance(code, amount, formData.get('passenger'))
    form.querySelector('.result-msg').innerText = result instanceof Error ? result.message : 'Your purchase processed successfully.'
  })
}

function onSubmitToOracles() {
  document.getElementById('submit-oracle').addEventListener('click', async function (e) {
    e.preventDefault()
    const form = document.forms['flight-status-check']
    const formData = new FormData(form)
    const code = formData.get('code').toUpperCase()
    const result = await context.get('contract').fetchFlightStatus(code)
    form.querySelector('.result-msg').innerText = result instanceof Error ? result.message : 'Request submitted successfully.'
  })
}

function onRegisterFlight() {
  const owner = context.get('contract').owner
  const members = context.get('contract').memberAirlines
  const selectBoxAirline = document.getElementById('flight-airline')
  selectBoxAirline.innerHTML = context.get('contract').airlines
    .map((addr, i) => `<option value="${addr}">(${members.indexOf(addr) !== -1 ? 'Member ' : ''}Airline ${i+1}) ${addr.toString().slice(0, 12)}...</option>`)
    .join(' ')
  const selectBoxFrom = document.getElementById('register-flight-from')
  selectBoxFrom.innerHTML = `<option value="${owner}">Owner</option>`
  selectBoxFrom.innerHTML += context.get('contract').airlines
    .map((addr, i) => `<option value="${addr}">(${members.indexOf(addr) !== -1 ? 'Member ' : ''}Airline ${i+1}) ${addr.toString().slice(0, 12)}...</option>`)
    .join(' ')

  document.getElementById('register-flight').addEventListener('click', async function (e) {
    e.preventDefault()
    const form = document.forms['register-flight']
    const formData = new FormData(form)
    const code = formData.get('code').toUpperCase()
    const departure = Math.floor(new Date(formData.get('departure')).getTime() / 1000)
    const result = await context.get('contract').registerFlight(formData.get('airline'), code, departure, formData.get('from'))
    form.querySelector('.result-msg').innerText = result instanceof Error ? result.message : 'Flight registered successfully.'
  })
}

function populateDepartureTime() {
  const input = document.getElementById('departure-time')
  input.value = new Date(Date.now() + 60000).toISOString()
}

function onRegisterAirline() {
  const owner = context.get('contract').owner
  const members = context.get('contract').memberAirlines
  const selectBoxFrom = document.getElementById('register-airline-from')
  selectBoxFrom.innerHTML = `<option value="${owner}">Owner</option>`
  selectBoxFrom.innerHTML += context.get('contract').airlines
    .map((addr, i) => `<option value="${addr}">(${members.indexOf(addr) !== -1 ? 'Member ' : ''}Airline ${i+1}) ${addr.toString().slice(0, 12)}...</option>`)
    .join(' ')

  document.getElementById('register-airline').addEventListener('click', async function (e) {
    e.preventDefault()
    const form = document.forms['register-airline']
    const formData = new FormData(form)
    const result = await context.get('contract').registerAirline(formData.get('airline'), formData.get('from'))
    form.querySelector('.result-msg').innerText = result instanceof Error ? result.message : 'Airline registered successfully.'
  })
}

function startOperationalStatusChecker() {
  setInterval(async () => {
    await check()
  }, 60000)

  check()

  async function check() {
    const isOperational = await context.get('contract').isOperational()
    document.getElementById('system-status').innerText = isOperational ? 'operational' : 'not operational'
  }
}