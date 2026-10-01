use mirrorrust::{connect_tls_mirror,run_client_validate_transport,spec_from_file,ApalacheConfig,TlsOptions};
fn main(){
 let e=|n:&str| std::env::var(n).expect(n);
 let mut tls=TlsOptions::new(e("MIRRORS_REMOTE_CA"),e("MIRRORS_REMOTE_CLIENT_CERT"),e("MIRRORS_REMOTE_CLIENT_KEY"));
 tls.pin=Some(e("MIRRORS_REMOTE_SERVER_PIN"));
 let result=(|| {
  let t=connect_tls_mirror("172.20.208.1",8999,&tls)?;
  let spec=spec_from_file(e("M5_INTEROP_SPEC"))?;
  let bound=e("M5_INTEROP_BOUND").parse::<u32>().unwrap();
  let config=ApalacheConfig{spec_path:"HourClock.tla".into(),invariant:e("M5_INTEROP_INV"),length_bound:i64::from(bound),const_init:None,init_predicate:Some("Init".into()),next_predicate:Some("Next".into()),param_vars:None};
  run_client_validate_transport(t,config,bound,Some(spec))
 })();
 match result {Ok(())=>println!("VALID"),Err(mirrorrust::Error::SpecInvalid(detail))=>{println!("INVALID\n{detail}");std::process::exit(1)},Err(error)=>{eprintln!("{error}");std::process::exit(2)}}
}
